import 'package:path/path.dart';
import 'package:async/async.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';

Future<String> fetchAuthHeader() async {
  var body = jsonEncode({'username': 'chucklan', 'password': 'password'});
  final response = await http.post(
      'https://boiling-plains-52145.herokuapp.com/login',
      headers: {"Content-Type": "application/json"},
      body: body);

  if (response.statusCode == 200) {
    // If the call to the server was successful, parse the JSON.
    return response.headers['authorization'].toString();
  } else {
    // If that call was not successful, throw an error.
    throw Exception('Failed to authenticate');
  }
}

Future<Ingredients> upload(File imageFile, String token) async {
  // open a bytestream
  var stream =
      new http.ByteStream(DelegatingStream.typed(imageFile.openRead()));
  // get file length
  var length = await imageFile.length();

  // string to uri
  var uri = Uri.parse(
      "https://boiling-plains-52145.herokuapp.com/ingredients/process/image");

  // create multipart request
  var request = new http.MultipartRequest("POST", uri);
  request.headers.addAll({'Authorization': token});

  // multipart that takes file
  var multipartFile = new http.MultipartFile('file', stream, length,
      filename: basename(imageFile.path));

  // add file to multipart
  request.files.add(multipartFile);

  // send
  var streamResponse = await request.send();
  var response = await http.Response.fromStream(streamResponse);
  var data = json.decode(response.body);
  var ingredients = Ingredients.fromJson(data);
  return ingredients;
  //return response.statusCode.toString();
  /*

  // listen for response
  response.stream.transform(utf8.decoder).listen((value) {
    print(value);
  });
  */
}

// A screen that takes in a list of cameras and the Directory to store images.
class TakePictureScreen extends StatefulWidget {
  final CameraDescription camera;

  const TakePictureScreen({
    Key key,
    @required this.camera,
  }) : super(key: key);

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  Future<String> authHeader;
  CameraController _controller;
  Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    authHeader = fetchAuthHeader();
    // To display the current output from the Camera,
    // create a CameraController.
    _controller = CameraController(
      // Get a specific camera from the list of available cameras.
      widget.camera,
      // Define the resolution to use.
      ResolutionPreset.medium,
    );

    // Next, initialize the controller. This returns a Future.
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Icon(Icons.camera_alt, size: 40.0)),
      // Wait until the controller is initialized before displaying the
      // camera preview. Use a FutureBuilder to display a loading spinner
      // until the controller has finished initializing.
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // If the Future is complete, display the preview.
            return CameraPreview(_controller);
          } else {
            // Otherwise, display a loading indicator.
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.camera_alt),
        // Provide an onPressed callback.
        onPressed: () async {
          // Take the Picture in a try / catch block. If anything goes wrong,
          // catch the error.
          try {
            // Ensure that the camera is initialized.
            await _initializeControllerFuture;

            // Construct the path where the image should be saved using the
            // pattern package.
            final path = join(
              // Store the picture in the temp directory.
              // Find the temp directory using the `path_provider` plugin.
              (await getTemporaryDirectory()).path,
              '${DateTime.now()}.png',
            );

            // Attempt to take a picture and log where it's been saved.
            await _controller.takePicture(path);

            final Future<Ingredients> ingred =
                upload(File(path), await authHeader);

            // If the picture was taken, display it on a new screen.
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    DisplayResultsScreen(ingredients: ingred, imagePath: path),
              ),
            );
          } catch (e) {
            // If an error occurs, log the error to the console.
            print(e);
          }
        },
      ),
    );
  }
}

class DisplayResultsScreenState extends State<DisplayResultsScreen>
    with SingleTickerProviderStateMixin {
  TabController _tabController;
  String imagePath;
  DisplayResultsScreenState(Future<Ingredients> ingredients, String imagePath) {
    this.ingredients = ingredients;
    this.imagePath = imagePath;
  }
  Future<Ingredients> ingredients;

  @override
  void initState() {
    _tabController = new TabController(length: 3, vsync: this);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text('Allergens', style: TextStyle(fontSize: 30.0)),
          bottom: TabBar(
            unselectedLabelColor: Colors.white,
            labelColor: Colors.grey,
            tabs: [
              Icon(Icons.find_in_page),
              Icon(Icons.photo),
              Icon(Icons.translate)
            ],
            controller: _tabController,
          )),
      body: Center(
        child: FutureBuilder<Ingredients>(
          future: ingredients,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return TabBarView(children: [
                ListView.builder(
                  itemCount: snapshot.data.allergens.length,
                  itemBuilder: (context, index) {
                    return Card(
                        child: ListTile(
                      title: Text(
                        snapshot.data.allergens[index]['name'],
                        style: TextStyle(fontSize: 20.0),
                      ),
                    ));
                  },
                ),
                Image.file(File(imagePath)),
                new SingleChildScrollView(
                    child: new Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                            (snapshot.data.translatedText != null)
                                ? snapshot.data.translatedText
                                : '',
                            style: TextStyle(fontSize: 20.0))))
              ], controller: _tabController);
            } else if (snapshot.hasError) {
              return Text("${snapshot.error}");
            }
            // By default, show a loading spinner.
            return CircularProgressIndicator();
          },
        ),
      ),
      // The image is stored as a file on the device. Use the `Image.file`
      // constructor with the given path to display the image.

      //body: Image.file(File(imagePath)),
    );
  }
}

// A widget that displays the picture taken by the user.
class DisplayResultsScreen extends StatefulWidget {
  final Future<Ingredients> ingredients;
  final String imagePath;

  const DisplayResultsScreen({Key key, this.ingredients, this.imagePath})
      : super(key: key);

  @override
  DisplayResultsScreenState createState() =>
      DisplayResultsScreenState(ingredients, imagePath);
}

class Ingredients {
  final String translatedText;
  final List<Map<String, dynamic>> ingredients;
  final List<Map<String, dynamic>> allergens;

  Ingredients({this.translatedText, this.ingredients, this.allergens});

  factory Ingredients.fromJson(Map<String, dynamic> parsedJson) {
    return new Ingredients(
        translatedText: parsedJson['translatedText'],
        ingredients:
            new List<Map<String, dynamic>>.from(parsedJson['ingredients']),
        allergens:
            new List<Map<String, dynamic>>.from(parsedJson['allergens']));
  }
}

/*class Ingredient {
  final String name;
  final String description;

  Ingredient({this.name, this.description});

  factory Ingredient.fromJson(Map<String, String> parsedJson) {
    return new Ingredient(
        name: parsedJson['name'], description: parsedJson['description']);
  }
}*/

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Obtain a list of the available cameras on the device.
  final cameras = await availableCameras();
  // Get a specific camera from the list of available cameras.
  final firstCamera = cameras.first;
  //runApp(MyApp());
  runApp(
    MaterialApp(
      theme: ThemeData.dark(),
      home: TakePictureScreen(
        // Pass the appropriate camera to the TakePictureScreen widget.
        camera: firstCamera,
      ),
    ),
  );
}
