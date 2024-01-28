import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../widgets/setting_tile.dart';
import '../utils/snackbar.dart';
import '../utils/constants.dart';
import '../utils/extra.dart';
import '../utils/customcharhelpers.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;
  final dataset;
  const DeviceScreen({Key? key, required this.device, required this.dataset}) : super(key: key);

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  int? _rssi;
  bool charReceived = false;

  late BluetoothCharacteristic myCharacteristic;
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  List<BluetoothService> _services = [];
  bool _isDiscoveringServices = false;
  bool _isConnecting = false;
  bool _isDisconnecting = false;

  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;
  @override
  void initState() {
    super.initState();

    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        _services = []; // must rediscover services
      }
      if (state == BluetoothConnectionState.connected && _rssi == null) {
        _rssi = await widget.device.readRssi();
      }
      if (mounted) {
        setState(() {});
      }
    });

    _isConnectingSubscription = widget.device.isConnecting.listen((value) {
      _isConnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isDisconnectingSubscription = widget.device.isDisconnecting.listen((value) {
      _isDisconnecting = value;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _isConnectingSubscription.cancel();
    _isDisconnectingSubscription.cancel();
    super.dispose();
  }

  bool get isConnected {
    return _connectionState == BluetoothConnectionState.connected;
  }

  Future onConnectPressed() async {
    try {
      await widget.device.connectAndUpdateStream();
      Snackbar.show(ABC.c, "Connect: Success", success: true);
      await onDiscoverServicesPressed();
    } catch (e) {
      if (e is FlutterBluePlusException && e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
      }
    }
  }

  bool valuesRecieved() {
    Map c = widget.dataset[21]; // the last one in the original batch
    String test = c["value"] ?? " ";
    if (test == " ") {
      return false;
    } else {
      return true;
    }
  }

  Future onDisconnectPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream();
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Disconnect Error:", e), success: false);
    }
  }

  Future onDiscoverServicesPressed() async {
    if (mounted) {
      setState(() {
        _isDiscoveringServices = true;
      });
    }
    try {
      _services = await widget.device.discoverServices();
      await _findChar();
      await updateCustomCharacter(myCharacteristic, true, widget.dataset);
      Snackbar.show(ABC.c, "Discover Services: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
    }
    if (mounted) {
      setState(() {
        _isDiscoveringServices = false;
      });
    }
  }

  Future onSaveSettingsPressed() async {
    try {
      await saveAllSettings(myCharacteristic, widget.dataset);
      Snackbar.show(ABC.c, "Settings Saved", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Save Settings Failed ", e), success: false);
    }
  }

  Future onSaveLocalPressed() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('user', jsonEncode(widget.dataset));
      Snackbar.show(ABC.c, "Settings Saved", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Save Local Failed ", e), success: false);
    }
  }

  Future onLoadLocalPressed() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      var _tdataset = jsonDecode(prefs.getString('user')!);
      await _tdataset.forEach((v) => findNSave(myCharacteristic, v, v["vName"]));
      //widget.dataset = jsonDecode(prefs.getString('user')!);

      Snackbar.show(ABC.c, "Settings Loaded", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Load local failed. Do you have a backup?", e), success: false);
    }
  }

  Future onRebootPressed() async {
    try {
      await reboot(myCharacteristic, widget.dataset);
      Snackbar.show(ABC.a, "SmartSpin2k is rebooting", success: true);
      await onDisconnectPressed();
      await onConnectPressed();
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Reboot Failed ", e), success: false);
    }
  }

  Future onResetPressed() async {
    try {
      await resetToDefaults(myCharacteristic, widget.dataset);
      await discoverServices();
      Snackbar.show(ABC.c, "SmartSpin2k has been reset to defaults", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Reset Failed ", e), success: false);
    }
  }

  Future discoverServices() async {
    if (mounted) {
      setState(() {
        _isDiscoveringServices = true;
      });
    }
    if (widget.device.isConnected) {
      try {
        _services = await widget.device.discoverServices();
        _findChar();
        await updateCustomCharacter(myCharacteristic, true, widget.dataset);
        Snackbar.show(ABC.c, "Discover Services: Success", success: true);
      } catch (e) {
        Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
      }
    }
    if (mounted) {
      setState(() {
        _isDiscoveringServices = false;
      });
    }
  }

  Widget buildSpinner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: CircularProgressIndicator(
          //backgroundColor: Colors.black12,
          //color: Colors.black26,
          ),
    );
  }

  Widget buildRemoteId(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text('${widget.device.remoteId}'),
    );
  }

  Widget buildRssiTile(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        isConnected ? const Icon(Icons.bluetooth_connected) : const Icon(Icons.bluetooth_disabled),
        Text(((isConnected && _rssi != null) ? '${_rssi!} dBm' : ''), style: Theme.of(context).textTheme.bodySmall)
      ],
    );
  }

  Widget buildUpdateValues(BuildContext context) {
    return IndexedStack(
      index: (_isDiscoveringServices) ? 1 : 0,
      children: <Widget>[
        isConnected
            ? OutlinedButton(
                child: const Text("Refresh\nValues", textAlign: TextAlign.center),
                onPressed: onDiscoverServicesPressed,
              )
            : Text(" "),
        const IconButton(
          icon: SizedBox(
            child: CircularProgressIndicator(
                //valueColor: AlwaysStoppedAnimation(Colors.grey),
                ),
            width: 18.0,
            height: 18.0,
          ),
          onPressed: null,
        )
      ],
    );
  }

  Widget buildSaveButton(context) {
    return OutlinedButton(
      child: const Text("Save To\nSS2k", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
      style: OutlinedButton.styleFrom(
        backgroundColor: Color.fromARGB(255, 0, 109, 11),
      ),
      onPressed: () {
        onSaveSettingsPressed();
        setState(() {});
      },
    );
  }

  Widget buildSaveLocalButton(context) {
    return OutlinedButton(
        child: const Text("Backup\nSettings", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
        style: OutlinedButton.styleFrom(
          backgroundColor: Color.fromARGB(255, 16, 3, 255),
        ),
        onPressed: () {
          onSaveLocalPressed();
          setState(
            () {},
          );
        });
  }

  Widget buildLoadLocalButton(context) {
    return OutlinedButton(
        child: const Text("Load\nBackup", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
        style: OutlinedButton.styleFrom(
          backgroundColor: Color.fromARGB(255, 16, 3, 255),
        ),
        onPressed: () {
          onLoadLocalPressed();
          setState(() {});
        });
  }

  Future waitToSetState(context) async {
    await Future.delayed(Duration(seconds: 10));
    setState(() {});
  }

  buildRebootButton(context) {
    return OutlinedButton(
        child: const Text(" Reboot\nSS2k ", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
        style: OutlinedButton.styleFrom(
          backgroundColor: Color.fromARGB(255, 255, 3, 3),
        ),
        onPressed: () {
          onRebootPressed();
          waitToSetState(context);
        });
  }

  buildResetButton(context) {
    return OutlinedButton(
        child: const Text("Set\nDefaults", textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
        style: OutlinedButton.styleFrom(
          backgroundColor: Color.fromARGB(255, 225, 214, 10),
        ),
        onPressed: () {
          onResetPressed();
          setState(() {});
        });
  }

  Future _findChar() async {
    while (!charReceived) {
      try {
        BluetoothService cs = _services.first;
        for (BluetoothService s in _services) {
          if (s.uuid == Guid(csUUID)) {
            cs = s;
            break;
          }
        }
        List<BluetoothCharacteristic> characteristics = cs.characteristics;
        for (BluetoothCharacteristic c in characteristics) {
          if (c.uuid == Guid(ccUUID)) {
            myCharacteristic = c;
            break;
          }
        }
        charReceived = true;
      } catch (e) {
        Snackbar.show(ABC.c, prettyException("No Services", e), success: false);
      }
    }
  }

//Build the settings dropdowns
  List<Widget> buildSettings(BuildContext context) {
    List<Widget> settings = [];
    if (charReceived && valuesRecieved()) {

      _newEntry(Map c) {
        if (!_services.isEmpty) {
          if (c["isSetting"]) {
            settings.add(SettingTile(characteristic: myCharacteristic, c: c, dataset: widget.dataset));
          }
        }
      }
      widget.dataset.forEach((c) => _newEntry(c));
    } else {
      if(!_isDiscoveringServices){
      discoverServices();
      setState(() {});}
    }
    return settings;
  }

  Widget buildConnectButton(BuildContext context) {
    return Row(
      children: [
        (_isConnecting || _isDisconnecting)
            ? buildSpinner(context)
            : OutlinedButton(
                onPressed: (isConnected ? onDisconnectPressed : onConnectPressed),
                child: Text((isConnected ? "DISCONNECT" : "CONNECT"),
                    textAlign: TextAlign.center, style: TextStyle(color: Color(0xfffffffff))),
                style: isConnected
                    ? OutlinedButton.styleFrom(
                        backgroundColor: Color.fromARGB(255, 255, 3, 3),
                      )
                    : OutlinedButton.styleFrom(
                        backgroundColor: Color.fromARGB(255, 25, 113, 0),
                      ))
      ],
      mainAxisAlignment: MainAxisAlignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.platformName),
          centerTitle: true,
          //  backgroundColor: Color.fromARGB(255, 1, 37, 244),
          //  foregroundColor: Color.fromARGB(255, 255, 255, 255)
        ),
        //actions: [buildConnectButton(context)],

        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              buildRemoteId(context),
              ListTile(
                leading: buildRssiTile(context),
                title: buildConnectButton(context),
                trailing: buildUpdateValues(context),
                titleAlignment: ListTileTitleAlignment.center,
              ),
              isConnected
                  ? Row(children: <Widget>[
                      buildRebootButton(context),
                      buildResetButton(context),
                      buildSaveButton(context),
                      buildSaveLocalButton(context),
                      buildLoadLocalButton(context),
                    ], mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center)
                  : SizedBox(),
              ...buildSettings(context),
            ],
          ),
        ),
      ),
    );
  }
}
