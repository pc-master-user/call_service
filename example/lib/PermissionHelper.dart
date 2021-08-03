/*
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  static const Permission storage= Permission.storage;
  static const Permission camera= Permission.camera;
  static const Permission microPhone= Permission.microphone;
  static const Permission location= Permission.location;
  static const Permission phone= Permission.phone;


  static Future<bool> requestStoragePermission() async{
    return await checkAndRequestForPermission(storage);
  }

  static Future<bool> requestCameraPermission() async{
    return await checkAndRequestForPermission(camera);
  }
  static Future<bool> requestMicroPhonePermission() async{
    return await checkAndRequestForPermission(microPhone);
  }

  static Future<bool> requestPhonePermission() async{
    return await checkAndRequestForPermission(microPhone);
  }

  static Future<bool> checkAndRequestForPermission(Permission permission) async{
    var status = await permission.status;
    if(status.isGranted){
      return true;
    }else if(status.isDenied){
      return await permission.request().isGranted;
    }
    return false;
  }
}
*/
