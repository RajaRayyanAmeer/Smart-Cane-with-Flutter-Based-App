import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const SmartCaneApp());

class SmartCaneApp extends StatelessWidget {
  const SmartCaneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Cane',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const BluetoothConnectionScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BluetoothConnectionScreen extends StatefulWidget {
  const BluetoothConnectionScreen({super.key});

  @override
  State<BluetoothConnectionScreen> createState() =>
      _BluetoothConnectionScreenState();
}

class _BluetoothConnectionScreenState extends State<BluetoothConnectionScreen>
    with SingleTickerProviderStateMixin {
  BluetoothConnection? _connection;
  String _connectionStatus = 'Not Connected';
  bool _isConnecting = false;
  bool _isConnected = false;

  // Live sensor data
  String obstacleStatus = '';
  String pitStatus = '';
  String modeStatus = '';
  String distanceStatus = '';
  String locationString = '';

  late AnimationController _iconAnimation;

  @override
  void initState() {
    super.initState();
    _checkBluetoothState();
    _iconAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _disconnect();
    _iconAnimation.dispose();
    super.dispose();
  }

  Future<void> _checkBluetoothState() async {
    bool isEnabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
    if (!isEnabled) {
      await FlutterBluetoothSerial.instance.requestEnable();
    }
  }

  Future<void> _connect() async {
    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Searching for device...';
    });

    try {
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();

      BluetoothDevice? device = devices.firstWhere(
        (d) => d.name == "HC-05",
        orElse: () => devices.isNotEmpty
            ? devices[0]
            : throw "No devices paired. Please pair HC-05 in settings.",
      );

      setState(() {
        _connectionStatus = 'Connecting to ${device.name}...';
      });

      _connection = await BluetoothConnection.toAddress(device.address);

      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _connectionStatus = 'Connected to ${device.name}';
      });

      _iconAnimation.forward();

      _connection!.input!.listen((data) {
        String message = String.fromCharCodes(data).trim();
        _parseData(message);
      }).onDone(() {
        _disconnect();
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'Connection failed: $e';
        _isConnecting = false;
        _isConnected = false;
      });
    }
  }

  Future<void> _disconnect() async {
    if (_connection != null) {
      await _connection?.close();
      _connection = null;
    }

    setState(() {
      _isConnecting = false;
      _isConnected = false;
      _connectionStatus = 'Disconnected';
    });

    _iconAnimation.reverse();
  }

  void _parseData(String message) {
    setState(() {
      if (message.contains("Obstacle:")) obstacleStatus = message;
      if (message.contains("PitHole:")) pitStatus = message;
      if (message.contains("Mode:")) modeStatus = message;
      if (message.contains("Distance:")) distanceStatus = message;
      if (message.contains("Location:")) locationString = message;
    });
  }

  void _openMap() {
    if (locationString.contains("Location:")) {
      try {
        final coords = locationString.replaceAll("Location:", "").trim();
        final parts = coords.split(",");
        String latRaw = parts[0].trim().split(" ")[0];
        String lonRaw = parts[1].trim().split(" ")[0];

        double lat = _convertNMEAToDecimal(latRaw);
        double lon = _convertNMEAToDecimal(lonRaw);

        final Uri googleMapsUrl =
            Uri.parse("https://www.google.com/maps?q=$lat,$lon");
        launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint("Error parsing location: $e");
      }
    }
  }

  double _convertNMEAToDecimal(String nmea) {
    if (nmea.length < 4) return 0.0;
    double deg = double.parse(nmea.substring(0, nmea.length - 7));
    double min = double.parse(nmea.substring(nmea.length - 7)) / 60;
    return deg + min;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Cane Bluetooth'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: AnimatedIcon(
              icon: AnimatedIcons.event_add,
              progress: _iconAnimation,
              color: _isConnected ? Colors.greenAccent : Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Icon(
                  _isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  size: 100,
                  color: _isConnected ? Colors.green : Colors.blueGrey,
                ),
                const SizedBox(height: 20),
                Text(
                  _connectionStatus,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
                _buildDataCard("Obstacle Status", obstacleStatus),
                _buildDataCard("PitHole Status", pitStatus),
                _buildDataCard("Mode", modeStatus),
                _buildDataCard("Distance", distanceStatus),
                _buildDataCard("Location", locationString,
                    action: _openMap, actionLabel: "View on Map"),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  icon: Icon(
                      _isConnected ? Icons.close : Icons.bluetooth_searching),
                  label: Text(_isConnected ? 'Disconnect' : 'Connect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Colors.red : Colors.blue,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 24),
                  ),
                  onPressed: _isConnected ? _disconnect : _connect,
                ),
              ],
            ),
          ),
          if (_isConnecting)
            Container(
              color: const Color.fromRGBO(0, 0, 0, 0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      "Connecting to Smart Cane...",
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDataCard(String title, String value,
      {VoidCallback? action, String? actionLabel}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(value.isNotEmpty ? value : "No data"),
        trailing: action != null
            ? TextButton(
                onPressed: action,
                child: Text(actionLabel ?? "Action"),
              )
            : null,
      ),
    );
  }
}
