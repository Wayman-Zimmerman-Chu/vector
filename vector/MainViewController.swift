//
//  MainViewController.swift
//  vector
//
//  Created by David Wayman on 3/14/16.
//  Copyright © 2016 WayZimChu. All rights reserved.
//

import UIKit
import Foundation
import CoreLocation
import GoogleMaps
import Parse
import MBProgressHUD

class MainViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate, LocationDetailsViewControllerDelegate {
	var placeArray: GooglePlace?
	var dataMachine = GoogleDataProvider()
	var placesClient: GMSPlacesClient?
	var time: NSDate?
	var users: [PFObject]?
	var myOwnObject: PFObject? //All update functions revolve around this object.
    var polyline: GMSPolyline?
    var huddie: MBProgressHUD?
    var coordinatesDict = [String : CLLocationCoordinate2D]()
    
	let meetingPlaceTypes = ["bakery", "bar", "cafe", "grocery_or_supermarket", "restaurant"]
	
	let searchRadius: Double = 1500
	
	@IBOutlet weak var mapView: GMSMapView!
	@IBOutlet weak var tableView: UITableView!
	@IBOutlet weak var markerInfoView: MarkerInfoView!

	var locationManager = CLLocationManager()
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		// Do any additional setup after loading the view.
		tableView.delegate = self
		tableView.dataSource = self
        tableView.allowsMultipleSelection = true
        
		mapView.delegate = self
		locationManager.delegate = self
		locationManager.requestWhenInUseAuthorization()
		placesClient = GMSPlacesClient()
		//print(users)
		// fetchLocations()
        
		let priority = DISPATCH_QUEUE_PRIORITY_DEFAULT
		dispatch_async(dispatch_get_global_queue(priority, 0)) {
			// do some task
			self.recursiveUpdate()
			dispatch_async(dispatch_get_main_queue()) {
				// update some UI
			}
		}
        //print("#### \(users)")
        self.tableView.reloadData()
    }
	
	override func viewWillAppear(animated: Bool) {
        self.addSlideMenuButton()
        print("%%%%% \((PFUser.currentUser()?.username!)!)")
        loadOwnObject((PFUser.currentUser()?.username!)!)
        coordinatesDict.removeAll()
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}
    
    /**
     *  Protocol method for receiving encoded poly line from details view
     */
    func vectored(controller: LocationDetailsViewController, encodedPolyline: String) {
        navigationController?.popToViewController(self, animated: true)
        //print("got the encoded polyline back: \(encodedPolyline)")
        //clear the map of extraneous information
        //mapView.clear()
        //create a GMSPath from the encoded polyline taken from GoogleDirections API
        let path = GMSPath(fromEncodedPath: encodedPolyline)
        //create a bounds for the camera to zoom to
        let coordinateBounds = GMSCoordinateBounds(path: path!)
        //create a cameraUpdate object for moving the camera
        let cameraUpdate = GMSCameraUpdate.fitBounds(coordinateBounds, withPadding: 80.0)
        //move camera to bounds
        mapView.moveCamera(cameraUpdate)
        polyline?.map = nil
        //create polyline
        polyline = GMSPolyline(path: path)
        polyline?.strokeColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        polyline?.strokeWidth = 5
        //put polyline on map
        polyline?.map = mapView
        
        // Clear dictionary of coordinates
        coordinatesDict.removeAll()
        
        let alert = UIAlertController(title: "Vectored", message: "Relax and drive safe.", preferredStyle: .Alert)
        let OKAction = UIAlertAction(title: "OK", style: .Default) { (action) in
            // It will dismiss itself
        }
        alert.addAction(OKAction)
        self.presentViewController(alert, animated: true, completion: nil)
    }
    
    
	/**
     *  Recursive function is sent to background to update own location
     */
	func recursiveUpdate()
	{
		NSThread.sleepForTimeInterval(10)
		if let selfID = (self.myOwnObject?.objectId) {
		if let location = locationManager.location?.coordinate {
		print("recursively updating: " + selfID)

		Post.updateLocation((myOwnObject?.objectId!)!, long: (location.longitude), lat: (location.latitude))
		NSThread.sleepForTimeInterval(30)
		} else {
			print("recursion failed: could not find coordinates")
			NSThread.sleepForTimeInterval(10)
		}
        }
		recursiveUpdate()
	}
	
    /*
     * MARK: - number of rows in selection for tableView
     */
	func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if let users = users {
			return users.count
		} else {
			return 0
		}
	}
	
   /*
    * MARK: - Cell for row at indexPath
    */
	func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("MainViewCell", forIndexPath: indexPath) as! MainViewCell
		let user = users![indexPath.row]
        
		cell.nameLabel.text = user["username"] as? String
        let otherLocation = CLLocation(latitude: user["latitude"] as! Double, longitude: user["longitude"] as! Double)
        var distance = locationManager.location!.distanceFromLocation(otherLocation)
        //print(distance)
        distance = distance/1600 // 1600 because it's in meters
        cell.distanceLabel.text = NSString(format: "%.2f miles away", distance) as String
        
		if let profile = user.valueForKey("profilePic")! as? PFFile {
			profile.getDataInBackgroundWithBlock({
				(imageData: NSData?, error: NSError?) -> Void in
				if (error == nil) {
					let image = UIImage(data:imageData!)
					cell.profileImage.image = image
                    
                    // Make profile picture circular
                    cell.profileImage.layer.masksToBounds = false
                    cell.profileImage.layer.cornerRadius = cell.profileImage.frame.height/2
                    cell.profileImage.clipsToBounds = true
					
					//print("Profile Picture Loaded")
				}
			})
		}
		
		return cell
	}
	
   /*
    * MARK: - Did select row at indexPath
    */
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        mapView.clear()
        let otherUser = users![indexPath.row]
        let myLocation = locationManager.location?.coordinate
        let otherLocation = CLLocationCoordinate2DMake(otherUser["latitude"] as! Double, otherUser["longitude"] as! Double)
        
        // Add coordinates to the dictionary
        coordinatesDict.updateValue(myLocation!, forKey: "my_coordinates")
        coordinatesDict.updateValue(otherLocation, forKey: "\(otherUser["lowercaseUsername"]!)")
        
        // Calculate midpoint
        let midpoint = calculateMidpoint(coordinatesDict)
        
        fetchLocations(midpoint)
        mapView.animateToLocation(midpoint)
        
        let cell = tableView.cellForRowAtIndexPath(indexPath)
        // UIView.animateWithDuration( 2, delay: 0.5, options: [UIViewAnimationOptions.CurveEaseInOut, UIViewAnimationOptions.Autoreverse, UIViewAnimationOptions.Repeat], animations: { cell!.alpha = 0.5}, completion: nil)

        //
        //animate the cell while selected
        //
        //
    }
    
   /*
    * MARK: - Did deselect row at indexPath
    */
    func tableView(tableView: UITableView, didDeselectRowAtIndexPath indexPath: NSIndexPath) {
        mapView.clear()
        
        let otherUser = users![indexPath.row]
        
        // Deselected, so let's remove their coordinates from the coordinate dictionary
        coordinatesDict.removeValueForKey("\(otherUser["lowercaseUsername"]!)")
        
        // Recalculate the midpoint
        let midpoint = calculateMidpoint(coordinatesDict)
        fetchLocations(midpoint)
        mapView.animateToLocation(midpoint)
        
        tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .None)
        
    }
	
    func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        //1. Setup the CATransform3D structure
        var rotation = CATransform3D()
        rotation = CATransform3DMakeRotation( CGFloat((60.0*M_PI)/180.0), 0.0, 0.7, 0.4);
        rotation.m34 = (1.0 / (-600))
        
        //2. Define the initial state (Before the animation)
        cell.layer.shadowColor = UIColor.blackColor().CGColor
        cell.layer.shadowOffset = CGSizeMake(10, 10);
        cell.alpha = 0;
        
        cell.layer.transform = rotation;
        cell.layer.anchorPoint = CGPointMake(0, 0.5);
        
        //3. Define the final state (After the animation) and commit the animation
        UIView.beginAnimations("rotation", context: nil)
        UIView.setAnimationDuration(0.8)
        cell.layer.transform = CATransform3DIdentity;
        cell.alpha = 1;
        cell.layer.shadowOffset = CGSizeMake(0, 0);
        UIView.commitAnimations()
    }

	func fetchLocations(coord: CLLocationCoordinate2D) {
        let loadingNotification = MBProgressHUD.showHUDAddedTo(self.view, animated: true)
        loadingNotification.mode = MBProgressHUDMode.Indeterminate
        loadingNotification.labelText = "Finding places :)"
        dataMachine.fetchPlacesNearCoordinate(coord, radius: searchRadius, types: meetingPlaceTypes) { places in
			for place: GooglePlace in places {
				let marker = PlaceMarker(place: place)
				//let markerView = MarkerInfoView()
				//print("places \(places.count)")
				// marker icon control
                    marker.title = place.name
				if let placeImage = UIImage(named: place.placeType)?.imageWithRenderingMode(.AlwaysTemplate) {
					marker.icon = placeImage
				} else {
					marker.icon = UIImage(named: "Generic")
				}
				
				marker.map = self.mapView
			}
            self.mapView.camera = GMSCameraPosition(target: coord, zoom: 13.5, bearing: 0, viewingAngle: 45)
			MBProgressHUD.hideHUDForView(self.view, animated: true)
		}
        
	}
	
    /* MARK: - Midpoint Function
     *         Calculates midpoint between all coordinates in an array
     *         Parameters: An array of CLLocationCoordinate2D
     */
    func calculateMidpoint(dictOfCoordinates: [String : CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
		// TEST DATA:::
		//let yourLocation = CLLocationCoordinate2DMake(37.7258391,-122.4507056) // CCSF Coordinates
		//let friend1Loc = CLLocationCoordinate2DMake(37.8049393,-122.4233581) // David's old address
        
        // Convert dictionary of coordinates into array of coordinates
        var arrayOfCoordinates = [CLLocationCoordinate2D]()
        
        for coordinates in dictOfCoordinates.values {
            arrayOfCoordinates.append(coordinates)
        }

		let onlineCoordinates = arrayOfCoordinates
		
		// Let's calculate the center of gravity of everything in the onlineCoordinates array
		let π = M_PI
		var numCoordinates: Int = 0
		var combinedCartesianX: Double = 0.0
		var combinedCartesianY: Double = 0.0
		var combinedCartesianZ: Double = 0.0
		
		// Iterate through all online friends' coordinates
		for (location) in onlineCoordinates {
			numCoordinates++
			//print("Lat: \(location.latitude) | Long: \(location.longitude)")
			let latRadians = location.latitude * (π/180)   // Convert Latitude to Radians
			let longRadians = location.longitude * (π/180) // Convert Longitude to Radians
			//print("latRadians: \(latRadians)")
			//print("longRadians: \(longRadians)")
			
			// Convert latitude and longitude to cartesian coordinates
			combinedCartesianX += (cos(latRadians) * cos(longRadians)) // Combined X Coordinate
			combinedCartesianY += (cos(latRadians) * sin(longRadians)) // Combined Y Coordinate
			combinedCartesianZ += sin(latRadians)
		}
		
		combinedCartesianX /= Double(numCoordinates)
		combinedCartesianY /= Double(numCoordinates)
		combinedCartesianZ /= Double(numCoordinates)
		//print("combinedCartesianX: \(combinedCartesianX)")
		//print("combinedCartesianY: \(combinedCartesianY)")
		//print("combinedCartesianZ: \(combinedCartesianZ)")
		
		let midpointX = atan2(combinedCartesianZ, (sqrt(pow(combinedCartesianX, 2) + pow(combinedCartesianY, 2))))
		let midpointY = atan2(combinedCartesianY, combinedCartesianX)
		
		let midpointLatitude = (180/π) * midpointX  // Convert from radians to degrees
		let midpointLongitude = (180/π) * midpointY // Convert from radians to degrees
		
		//print("Midpoint | Lat: \(midpointLatitude) | Long: \(midpointLongitude)")
		let midpoint = CLLocationCoordinate2DMake(midpointLatitude, midpointLongitude)
		
		return midpoint
	}
    
	/** loads profile owner's profile object so it can be updated
     *
     */
    func loadOwnObject(myName: String){
        var user:  PFObject?
        let query = PFQuery(className: "Profile")
        query.whereKey("username", containsString: myName)
        query.limit = 1
        query.findObjectsInBackgroundWithBlock {
            (object: [PFObject]?, error: NSError?) -> Void in
            user = object![0]
            if error == nil {
                //The find succeeded.
                //print("Successfully retrieved my own object \(user)")
                self.myOwnObject = user
                self.users = self.loadFriends()
            }
        }
    }
    
    /*
    func loadProfiles() -> [PFObject]? {
        
        var user: [PFObject]?
        let query = PFQuery(className:"Profile")
        //query.whereKey("name", equalTo: "\(name)")
        
        //This query will check to see who has your name under friends and return those profile objects
        query.whereKey("friends",   containedIn: ["\((PFUser.currentUser()?.username!)!)"])
        query.orderByDescending("createdAt")
        //query.includeKey("username")
        query.limit = 20
        query.findObjectsInBackgroundWithBlock {
            (objects: [PFObject]?, error: NSError?) -> Void in
            user = objects
            self.tableView.reloadData()
            if error == nil {
                // The find succeeded.
                print("Successfully retrieved \(objects!.count) Points In Time.")
                self.users = objects
                self.tableView.reloadData()
                
                if let objects = objects {
                    for object in objects {
                        //print(object.objectId)
                        print(object)
                    }
                }
            } else {
                // Log details of the failure
                print("Error: \(error!) \(error!.userInfo)")
            }
            self.tableView.reloadData()
        }
        self.tableView.reloadData()
        return user
        
    }
	*/
    
    /* MARK: - Load Friends
    * loads all PFObjects that are your friends
    */
    func loadFriends() -> [PFObject]? {
        var friends: [PFObject]?
        let friendUserNames = myOwnObject!.valueForKey("friends") as? [String]
        
        let query = PFQuery(className: "Profile")
        
        query.whereKey("lowercaseUsername", containedIn: friendUserNames!)
        query.orderByAscending("lowercaseUsername")
        query.limit = 50
        query.findObjectsInBackgroundWithBlock {
            (objects: [PFObject]?, error: NSError?) -> Void in
            friends = objects
            if error == nil {
                // The find succeeded!
                //print("FRIENDS::: Successfully retrieved \(objects!.count)")
                friends = objects
                self.users = friends
                self.tableView.reloadData()
                /*
                if let objects = objects {
                    for object in objects {
                       // print(object)
                    }
                }*/
            } else {
                // Log details of the failure
                print("Error: \(error!) \(error!.userInfo)")
            }
        }
        
        return friends
    }
    
	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "toFriendView" {
            let destinationNavigationController = segue.destinationViewController as! FriendsListViewController
            destinationNavigationController.myOwnObject = self.myOwnObject!
        } else if segue.identifier == "updateProfileSegue" {
            let destinationNavigationController = segue.destinationViewController as! ProfileViewController
            //print("MY OWN OBJECT:::::: \(myOwnObject)")
            destinationNavigationController.myOwnObject = self.myOwnObject!
        } else if segue.identifier == "toPlacesProfile" {
            let marker = sender as! PlaceMarker
            let destinationNavigationController = segue.destinationViewController as! LocationDetailsViewController
            destinationNavigationController.placeHolder = marker.place
            //print("place sent to Location View controller")
            //print(marker.place.name)
            destinationNavigationController.myObject = myOwnObject
            let sentView = segue.destinationViewController as! LocationDetailsViewController
            sentView.delegate = self
        }
    }
    
    /*
        MARK: - Old function for testing
        Calculates a midpoint

    @IBAction func onCalcPoint(sender: AnyObject) {
        // GO TO LOCATION DETAILS VIEW
        //print((locationManager.location?.coordinate)!)
        self.tableView.reloadData();
        fetchLocations((locationManager.location?.coordinate)!)
        placesClient?.currentPlaceWithCallback({
            (placeLikelihoodList: GMSPlaceLikelihoodList?, error: NSError?) -> Void in
            if let error = error {
                print("Pick Place error: \(error.localizedDescription)")
                return
            }
            
            //   self.nameLabel.text = "No current place"
            // self.addressLabel.text = ""
            
            if let placeLikelihoodList = placeLikelihoodList {
                let place = placeLikelihoodList.likelihoods.first?.place
                if let place = place {
                    //  self.nameLabel.text = place.name
                    // self.addressLabel.text = place.formattedAddress!.componentsSeparatedByString(", ")
                    // .joinWithSeparator("\n")
                    print("\(place.name) \(place.formattedAddress!.componentsSeparatedByString(", ").joinWithSeparator("\n"))")
                }
            }
        })
    }
    */
	
}

extension MainViewController: GMSMapViewDelegate {
    func mapView(mapView: GMSMapView, didTapInfoWindowOfMarker marker: GMSMarker) {
        print("tapped... nice")
        self.performSegueWithIdentifier("toPlacesProfile", sender: marker)
    }
    
	
	func didTapMyLocationButtonForMapView(mapView: GMSMapView) -> Bool {
            mapView.selectedMarker = nil
            mapView.camera = GMSCameraPosition(target: locationManager.location!.coordinate, zoom: 13, bearing: 0, viewingAngle: 0)
            return false
	}
}

extension MainViewController: CLLocationManagerDelegate {
	
	// called with authorization is granted or revoked
	func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
		
		// checks for location authorization
		if status == .AuthorizedWhenInUse {
			
			// updates live location
			locationManager.startUpdatingLocation()
			
			// enables blue loc dot & center on loc button
			mapView.myLocationEnabled = true
			mapView.settings.myLocationButton = true
		}
	}
	
	// called when new location data is received
	func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		
		if let location = locations.last {
			time = NSDate()
			// center camera on user location
			mapView.camera = GMSCameraPosition(target: location.coordinate, zoom: 13, bearing: 0, viewingAngle: 0)
			//fetchLocations(location.coordinate)
			
			// turns off location updates
			// TODO: probably want to set this on a timer
			locationManager.stopUpdatingLocation()
			//print("Got IT")
		}
		
	}
}

extension UIView {
	class func viewFromNibName(nibNamed: String, bundle : NSBundle? = nil) -> UIView? {
		return UINib(
			nibName: nibNamed,
			bundle: bundle
			).instantiateWithOwner(nil, options: nil)[0] as? UIView
	}
}
