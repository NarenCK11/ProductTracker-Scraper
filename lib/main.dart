import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'product_utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeService();
  runApp(MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'product_monitor_bg',
      initialNotificationTitle: 'Product Monitor',
      initialNotificationContent: 'Monitoring products in background',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Product Monitor',
      theme: ThemeData(
        primarySwatch: MaterialColor(0xFF6B46C1, {
          50: Color(0xFFF5F3FF),
          100: Color(0xFFEDE9FE),
          200: Color(0xFFDDD6FE),
          300: Color(0xFFC4B5FD),
          400: Color(0xFFA78BFA),
          500: Color(0xFF8B5CF6),
          600: Color(0xFF7C3AED),
          700: Color(0xFF6B46C1),
          800: Color(0xFF553C9A),
          900: Color(0xFF4C1D95),
        }),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF6B46C1),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF6B46C1),
          foregroundColor: Colors.white,
        ),
      ),
      home: ProductMonitorHome(),
    );
  }
}

class Product {
  final String id;
  final String url;
  final String title;
  final String price;
  final String availability;
  final DateTime lastChecked;
  final bool isAvailable;

  Product({
    required this.id,
    required this.url,
    required this.title,
    required this.price,
    required this.availability,
    required this.lastChecked,
    required this.isAvailable,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'price': price,
      'availability': availability,
      'lastChecked': lastChecked.toIso8601String(),
      'isAvailable': isAvailable,
    };
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      url: json['url'],
      title: json['title'],
      price: json['price'],
      availability: json['availability'],
      lastChecked: DateTime.parse(json['lastChecked']),
      isAvailable: json['isAvailable'],
    );
  }
}

class ProductMonitorHome extends StatefulWidget {
  @override
  _ProductMonitorHomeState createState() => _ProductMonitorHomeState();
}

class _ProductMonitorHomeState extends State<ProductMonitorHome> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  List<Product> products = [];
  Timer? monitoringTimer;
  String scraperApiKey = '';
  int checkInterval = 20; // minutes
  bool isMonitoring = false;
  bool isLoading = false;
  bool backgroundMonitoring = false;

  @override
  void initState() {
    super.initState();
    initializeNotifications();
    requestPermissions();
    loadSettings();
    loadProducts();
  }

  @override
  void dispose() {
    monitoringTimer?.cancel();
    super.dispose();
  }

  Future<void> requestPermissions() async {
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();
  }

  Future<void> initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        print('Notification tapped: ${response.payload}');
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'product_monitor',
      'Product Monitor',
      description: 'Notifications for product availability',
      importance: Importance.high,
    );

    const AndroidNotificationChannel bgChannel = AndroidNotificationChannel(
      'product_monitor_bg',
      'Product Monitor Background',
      description: 'Background notifications for product availability',
      importance: Importance.max,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(bgChannel);
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      scraperApiKey = prefs.getString('scraperApiKey') ?? '';
      checkInterval = prefs.getInt('checkInterval') ?? 20;
      backgroundMonitoring = prefs.getBool('backgroundMonitoring') ?? false;
    });
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('scraperApiKey', scraperApiKey);
    await prefs.setInt('checkInterval', checkInterval);
    await prefs.setBool('backgroundMonitoring', backgroundMonitoring);
  }

  Future<void> loadProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final productsJson = prefs.getStringList('products') ?? [];
    setState(() {
      products = productsJson
          .map((json) => Product.fromJson(jsonDecode(json)))
          .toList();
    });
  }

  Future<void> saveProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final productsJson = products
        .map((product) => jsonEncode(product.toJson()))
        .toList();
    await prefs.setStringList('products', productsJson);
  }

  Future<void> showNotification(String title, String body, {String? payload}) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'product_monitor',
      'Product Monitor',
      channelDescription: 'Notifications for product availability',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  Future<Product?> checkProductAvailability(String url) async {
    try {
      print("Checking product: $url");
      print("API Key: ${scraperApiKey.isNotEmpty ? 'Set' : 'Not Set'}");
      
      final response = await http.get(
        Uri.parse('https://api.scraperapi.com').replace(queryParameters: {
          'api_key': scraperApiKey,
          'url': url,
          'country_code': 'in',
          'render': 'true',
        }),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(Duration(seconds: 60));

      print("Response status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        
        String title = "Product Not Found";
        String price = "Price Not Found";
        String availability = "In Stock";
        bool isAvailable = true;

        if (url.contains('flipkart.com')) {
          title = ProductUtils.extractFlipkartTitle(document) ?? title;
          price = ProductUtils.extractFlipkartPrice(document) ?? price;
          availability = ProductUtils.extractFlipkartAvailability(document);
        } else if (url.contains('amazon.')) {
          title = ProductUtils.extractAmazonTitle(document) ?? title;
          price = ProductUtils.extractAmazonPrice(document) ?? price;
          availability = ProductUtils.extractAmazonAvailability(document);
        }

        isAvailable = !availability.toLowerCase().contains('out of stock');

        return Product(
          id: url.hashCode.toString(),
          url: url,
          title: title,
          price: price,
          availability: availability,
          lastChecked: DateTime.now(),
          isAvailable: isAvailable,
        );
      } else {
        print("HTTP Error: ${response.statusCode}");
        if (response.statusCode == 401) {
          throw Exception('Invalid API key');
        } else if (response.statusCode == 429) {
          throw Exception('Rate limit exceeded');
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      }
    } catch (e) {
      print('Error checking product: $e');
      throw e;
    }
  }

  void startMonitoring() {
    if (scraperApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please set your ScraperAPI key first')),
      );
      return;
    }

    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please add at least one product to monitor')),
      );
      return;
    }

    // Start foreground monitoring
    monitoringTimer = Timer.periodic(
      Duration(minutes: checkInterval),
      (timer) async {
        await checkAllProducts();
      },
    );

    // Start background monitoring if enabled
    if (backgroundMonitoring) {
      startBackgroundService();
    }

    setState(() {
      isMonitoring = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Monitoring started - checking every $checkInterval minutes')),
    );
  }

  Future<void> startBackgroundService() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    
    if (!isRunning) {
      await service.startService();
    }
    
    // Send data to the background service
    service.invoke('setAsForeground');
    service.invoke('start_task', {
      'checkInterval': checkInterval,
    });
  }

  void stopMonitoring() {
    monitoringTimer?.cancel();
    stopBackgroundService();
    
    setState(() {
      isMonitoring = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Monitoring stopped')),
    );
  }

  Future<void> stopBackgroundService() async {
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    
    if (isRunning) {
      service.invoke('stopService');
    }
  }

  Future<void> checkAllProducts() async {
    for (int i = 0; i < products.length; i++) {
      try {
        final updatedProduct = await checkProductAvailability(products[i].url);
        if (updatedProduct != null) {
          final wasUnavailable = !products[i].isAvailable;
          final isNowAvailable = updatedProduct.isAvailable;

          setState(() {
            products[i] = updatedProduct;
          });

          if (wasUnavailable && isNowAvailable) {
            await showNotification(
              '🎉 Product Available!',
              '${updatedProduct.title} is now in stock!',
              payload: updatedProduct.url,
            );
          }
        }
      } catch (e) {
        print('Error checking product ${products[i].title}: $e');
      }
      
      // Add delay between requests
      await Future.delayed(Duration(seconds: 5));
    }
    await saveProducts();
  }

  Future<void> checkSingleProduct(int index) async {
    setState(() {
      isLoading = true;
    });

    try {
      final updatedProduct = await checkProductAvailability(products[index].url);
      if (updatedProduct != null) {
        setState(() {
          products[index] = updatedProduct;
        });
        await saveProducts();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product updated successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update product: $e')),
      );
    }

    setState(() {
      isLoading = false;
    });
  }

  void addProduct(String url) async {
    if (url.isEmpty) return;

    setState(() {
      isLoading = true;
    });

    try {
      final product = await checkProductAvailability(url);
      if (product != null) {
        setState(() {
          products.add(product);
        });
        await saveProducts();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product added successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add product: $e')),
      );
    }

    setState(() {
      isLoading = false;
    });
  }

  void removeProduct(String id) {
    setState(() {
      products.removeWhere((product) => product.id == id);
    });
    saveProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Product Monitor'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: isLoading ? null : () async {
              await checkAllProducts();
            },
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: EdgeInsets.all(16),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Color(0xFF6B46C1).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Monitoring Status',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6B46C1),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            isMonitoring 
                                ? 'Active - Checking every $checkInterval minutes' 
                                : 'Stopped',
                            style: TextStyle(
                              color: isMonitoring ? Colors.green : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (products.isNotEmpty)
                            Text(
                              'Monitoring ${products.length} product${products.length > 1 ? 's' : ''}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: isMonitoring ? stopMonitoring : startMonitoring,
                      child: Text(isMonitoring ? 'Stop' : 'Start'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isMonitoring ? Colors.red : Color(0xFF6B46C1),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (backgroundMonitoring) ...[
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.cloud_sync, size: 16, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        'Background monitoring enabled',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (isLoading)
            Padding(
              padding: EdgeInsets.all(16.0),
              child: LinearProgressIndicator(),
            ),
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 80,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No products added yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap the + button to add a product',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return Card(
                        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: product.isAvailable 
                                ? Colors.green 
                                : Colors.red,
                            child: Icon(
                              product.isAvailable 
                                  ? Icons.check 
                                  : Icons.close,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            product.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Price: ${product.price}'),
                              Text('Status: ${product.availability}'),
                              Text(
                                'Last checked: ${DateFormat('HH:mm, dd/MM').format(product.lastChecked)}',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.refresh, color: Colors.blue),
                                onPressed: isLoading ? null : () => checkSingleProduct(index),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete, color: Colors.red),
                                onPressed: () => removeProduct(product.id),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddProductDialog,
        child: Icon(Icons.add),
      ),
    );
  }

  void _showAddProductDialog() {
    final TextEditingController urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Product'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: 'Product URL',
                hintText: 'Enter Flipkart or Amazon product URL',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            SizedBox(height: 8),
            Text(
              'Supported sites: Flipkart, Amazon',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              addProduct(urlController.text.trim());
              Navigator.of(context).pop();
            },
            child: Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    final TextEditingController apiKeyController = 
        TextEditingController(text: scraperApiKey);
    final TextEditingController intervalController = 
        TextEditingController(text: checkInterval.toString());
    bool tempBackgroundMonitoring = backgroundMonitoring;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: apiKeyController,
                decoration: InputDecoration(
                  labelText: 'ScraperAPI Key',
                  hintText: 'Enter your ScraperAPI key',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              SizedBox(height: 16),
              TextField(
                controller: intervalController,
                decoration: InputDecoration(
                  labelText: 'Check Interval (minutes)',
                  hintText: 'Enter check interval in minutes',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 16),
              CheckboxListTile(
                title: Text('Background Monitoring'),
                subtitle: Text('Keep monitoring when app is closed'),
                value: tempBackgroundMonitoring,
                onChanged: (value) {
                  setDialogState(() {
                    tempBackgroundMonitoring = value ?? false;
                  });
                },
              ),
              SizedBox(height: 8),
              Text(
                'Minimum recommended interval: 15 minutes for background monitoring',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  scraperApiKey = apiKeyController.text.trim();
                  int newInterval = int.tryParse(intervalController.text) ?? 20;
                  checkInterval = newInterval < 1 ? 1 : newInterval;
                  backgroundMonitoring = tempBackgroundMonitoring;
                });
                saveSettings();
                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Initialize Flutter plugins
  WidgetsFlutterBinding.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: initializationSettingsAndroid),
  );

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    service.on('start_task').listen((event) async {
      final checkInterval = event?['checkInterval'] ?? 20;
      
      while (true) {
        // Check if service should continue running
        if (service is AndroidServiceInstance) {
          final androidService = service as AndroidServiceInstance;
          if (await androidService.isForegroundService() == false) {
            break;
          }
        }
        
        try {
          // Get stored data
          final prefs = await SharedPreferences.getInstance();
          final apiKey = prefs.getString('scraperApiKey') ?? '';
          final productsJson = prefs.getStringList('products') ?? [];
          
          if (apiKey.isEmpty || productsJson.isEmpty) {
            print("No API key or products found");
            await Future.delayed(Duration(minutes: checkInterval));
            continue;
          }

          // Parse products
          List<Product> products = productsJson
              .map((json) => Product.fromJson(jsonDecode(json)))
              .toList();

          // Check each product
          bool hasUpdates = false;
          for (int i = 0; i < products.length; i++) {
            final updatedProduct = await _checkProductInBackground(products[i].url, apiKey);
            if (updatedProduct != null) {
              final wasUnavailable = !products[i].isAvailable;
              final isNowAvailable = updatedProduct.isAvailable;
              
              products[i] = updatedProduct;
              hasUpdates = true;

              // Send notification if product became available
              if (wasUnavailable && isNowAvailable) {
                await _showBackgroundNotification(
                  flutterLocalNotificationsPlugin,
                  '🎉 Product Available!',
                  '${updatedProduct.title} is now in stock!',
                );
              }
            }
            
            // Add delay between requests to avoid rate limiting
            await Future.delayed(Duration(seconds: 5));
          }

          // Save updated products
          if (hasUpdates) {
            final updatedProductsJson = products
                .map((product) => jsonEncode(product.toJson()))
                .toList();
            await prefs.setStringList('products', updatedProductsJson);
          }

          // Wait until next check
          await Future.delayed(Duration(minutes: checkInterval));
        } catch (e) {
          print("Background task error: $e");
          await Future.delayed(Duration(minutes: 5));
        }
      }
    });
  }
}

Future<Product?> _checkProductInBackground(String url, String apiKey) async {
  try {
    print("Checking product: $url");
    
    final response = await http.get(
      Uri.parse('https://api.scraperapi.com').replace(queryParameters: {
        'api_key': apiKey,
        'url': url,
        'country_code': 'in',
        'render': 'true',
      }),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ).timeout(Duration(seconds: 60));

    print("Response status: ${response.statusCode}");

    if (response.statusCode == 200) {
      final document = html_parser.parse(response.body);
      
      String title = "Product Not Found";
      String price = "Price Not Found";
      String availability = "In Stock";
      bool isAvailable = true;

      if (url.contains('flipkart.com')) {
    title = ProductUtils.extractFlipkartTitle(document) ?? title;
    price = ProductUtils.extractFlipkartPrice(document) ?? price;
    availability = ProductUtils.extractFlipkartAvailability(document);
} else if (url.contains('amazon.')) {
    title = ProductUtils.extractAmazonTitle(document) ?? title;
    price = ProductUtils.extractAmazonPrice(document) ?? price;
    availability = ProductUtils.extractAmazonAvailability(document);
}

      isAvailable = !availability.toLowerCase().contains('out of stock');

      return Product(
        id: url.hashCode.toString(),
        url: url,
        title: title,
        price: price,
        availability: availability,
        lastChecked: DateTime.now(),
        isAvailable: isAvailable,
      );
    } else {
      print("HTTP Error: ${response.statusCode} - ${response.body}");
    }
  } catch (e) {
    print('Error checking product in background: $e');
  }
  return null;
}

Future<void> _showBackgroundNotification(
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
  String title, 
  String body,
) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'product_monitor_bg',
    'Product Monitor Background',
    channelDescription: 'Background notifications for product availability',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
    icon: '@mipmap/ic_launcher',
  );
  
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
  
  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    platformChannelSpecifics,
  );
}