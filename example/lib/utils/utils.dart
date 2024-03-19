import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'dart:async';


 Future<void> requestPermissions() async {
    final permissions = [
      Permission.locationWhenInUse,
      Permission.bluetooth,
      if (Platform.isAndroid) ...[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        
      ],
    ];

    for (final permission in permissions) {
      final result = await permission.request();
      if (result == PermissionStatus.denied || result == PermissionStatus.permanentlyDenied) return;
    }
  }

  ///for displaying the processes
  void showSnackBar(String message,BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(message),
    ));
  }


  

