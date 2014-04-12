Overview
========

Cooliris ToolKit for iOS & OS X is a collection of Objective-C classes you can use to speed up development of your iOS and OS X applications. It is used in various [Cooliris](http://www.cooliris.com) products for iOS like [Discover](http://www.cooliris.com/ipad/discover) or [Decks](http://www.decksapp.com).

What makes Cooliris ToolKit different from various open-source toolkits is that each feature was designed to have minimal dependency on the other ones. Each feature was also designed to be implemented with a single .h/.m source code files pair. The combination of these 2 design goals makes it quite easy to re-use only what you need from this project without clustering your application with many additional obscure source files.

License
=======

Cooliris ToolKit is copyright 2011 Cooliris, Inc. and available under [Apache 2.0 license](http://www.apache.org/licenses/LICENSE-2.0.html). See the [LICENSE](LICENSE) file in the project for more information.

Clients & Examples
==================

These are  shipping iOS applications or examples that make significant use of the Cooliris ToolKit:
  * [Discover by Cooliris](http://www.cooliris.com/ipad/discover), a completely new way to explore Wikipedia, inviting you to sit back, relax, and expand your knowledge through a delightful experience that doesn't feel like you're reading an encyclopedia.
  * [Decks by Cooliris](http://www.decksapp.com), your brand new buying experience on iPad. Create and enjoy your own customized catalogs as intuitive decks of cards that update continuously — all in one place.
  * [Decks for Apps](http://itunes.apple.com/us/app/decks-for-apps/id432671386?mt=8), the simplest and fastest way to keep up to date on the top apps for iPad. With Decks for Apps, discovering new apps on the App Store has become a whole lot easier.
  * [Decks for Flickr](http://itunes.apple.com/us/app/decks-for-flickr/id432336526?mt=8), your whole new way to enjoy a rich, fluid photographic experience on iPad. Discover and follow public photos from Flickr that match your interest, all as intuitive decks of cards that update continuously.
  * [Decks for Movies](http://itunes.apple.com/us/app/decks-for-movies/id432336366?mt=8), the hassle-free way to catch movie trailers for the top movies all in one place.
  * [ComicFlow](http://itunes.apple.com/us/app/comicflow/id409290355?mt=8), a popular free iPad comic reader by [Pierre-Olivier Latour](http://www.pol-online.net) and available under open-source license at https://github.com/swisspol/ComicFlow.

If you have an application that would fit this list, make sure to let us know at feedback@cooliris.com.

Using Cooliris ToolKit
======================

You can of course cherry pick which classes you want in your project and copy the related source code files, but the easiest way it to have the entire Cooliris-Toolkit directory at the top-level of your project directory so you can easily keep up to date with the latest version.

Be aware that some classes have required matching assets in the Resources directory e.g. “GridView-Background.png” for GridView.h/m.

Directory Hierarchy
===================

Classes
-------

This directory is the core of the Cooliris Toolkit: these Objective-C classes have minimal dependencies between each others and should be ready-to-use in your projects.
  * **ApplicationDelegate**: This classes offers numerous built-in functionalities for a UIApplication delegate in cooperation with the Logging and Task classes. Your application delegate class should subclass this class instead of NSObject to benefit automatically from all these features.
  * **AutoresizingView**: UIView subclass that automatically resizes a content subview using a “center”, “resize”, “aspect-fit” or “aspect-fill” method.
  * **BackgroundThread**: Allows to start and wait for completion of background threads in an atomic way.
  * **BasicAnimation**: Simple CABasicAnimation subclass that allows to specify per-instance delegate and callbacks on animation completion.
  * **CameraViewController**: UIViewController subclass to replace UIImagePickerController to take photos with customizable user interface, image scaling and EXIF metadata (including GPS location) inclusion.
  * **Crypto**: Provides C function wrappers for MD5 and SHA2-256 hash computations.
  * **Database**: Implements a powerful SQLite Objectice-C wrapper with automatic schema creation from class properties.
  * **DataWrapper**: Simple NSData subclass that allows to wrap a block of memory and provide a custom C callback for release.
  * **DiskCache**: Manages a cache on disk of NSCoding compatible objects or raw data files which can be purged to a maximum size.
  * **DocumentView**: Displays and manages layout and user interaction of a set of “page-type” subviews arranged horizontally.
  * **ExtendedPageControl**: Implements a page control like the one on the home screen of iOS.
  * **Extensions_AmazonS3**: Category on NSMutableURLRequest to sign HTTP requests for Amazon S3.
  * **Extensions_CoreAnimation**: Categories on Core Animation classes to implement various convenience features.
  * **Extensions_Foundation**: Categories on Foundation classes to implement various convenience features.
  * **Extensions_UIKit**: Categories on UIKit classes to implement various convenience features.
  * **FileSystemView**: Subclass of GridView that displays the contents of a directory.
  * **FormTableController**: UITableView subclass that implements a form with text, password or checkbox fields.
  * **GridView**: Displays and manages layout and user interaction with a grid of subviews.
  * **HTTPURLConnection**: Subclass of NSURLConnection that implements synchronous HTTP operations and offers features like downloading to disk or resuming downloads. 
  * **ImageCell**: UITableViewCell subclass to display images.
  * **ImageUtilities**: Low-level C functions to perform graphic operations on CGImages.
  * **InfiniteView**: Displays and manages layout and user interaction of a set of “page-type” subviews arranged both horizontally and vertically in an infinite presentation.
  * **Keychain**: Objective-C wrapper to store and retrieve passwords from the Keychain.
  * **LibXMLParser**: Objective-C wrapper for LibXML.
  * **Logging**: Powerful logging facility with history recording and playback, and well as remote logging over Telnet.
  * **MapAnnotation**: Basic MKAnnotation conforming class to use with MapKit.
  * **MovieView**: Loads and displays a movie from a URL.
  * **NavigationControl**: Implements a navigation control with customizable markers and thumb.
  * **NetReachability**: Objective-C wrapper for the System Configuration reachability APIs.
  * **OverlayView**: Displays a simple pop-over view with an arrow at a given location.
  * **PubNub**: Clean and simple Objective-C interface for http://www.pubnub.com/.
  * **RichString**: Basic replacement for NSAttributedString that allows archiving of itself and its attachments.
  * **ServerConnection**: Provides an abstract state-machine for applications that needs to be continuously connected to a server and automatically reconnect / disconnect depending on network conditions.
  * **ShakeMotion**: Wrapper around UIAccelerometer to detect shake motions.
  * **SliderControl**: Implements a slider control with customizable graphic assets.
  * **SmartDescription**: Replacement for NSObject's -description that automatically prints the values of the object’s properties.
  * **SwitchCell**: UITableViewCell subclass to display switches.
  * **TextFieldCell**: UITableViewCell subclass to display text fields.
  * **TextIndex**: Offers a simple text indexer for Western languages.
  * **UnitTest**: Base class to implement unit tests.
  * **WebViewController**: UIViewController subclass that displays a UIWebView along with back and forward buttons.
  * **ZoomView**: Displays a content subview (typically a UIImageView) with automatic pan and zoom behavior.

Resources
---------

Associated resources required by the source code in the “Classes” directory.

Scripts
-------

A series of shell scripts to be used from Xcode script phases. The primary one is “PatchInfoPlist.sh” which conveniently replaces some predefined variables in “Info.plist” and associated “InfoPlist.strings” files.

UnitTests
---------

Stand-alone Xcode project to run the unit tests on Mac OS X for the source code in the “Classes” directory.

Xcode-Configurations
--------------------

Recommanded Xcode configurations for your iOS & OS X projects.
