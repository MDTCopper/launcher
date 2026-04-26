import 'package:flutter/foundation.dart';
import 'package:system_info2/system_info2.dart' as s;

class SysInfo {

  static Future<int> getFreePhysicalMemory (){
    return _futureBuilder<int>(()=>s.SysInfo.getFreePhysicalMemory());
  }

  static Future<R> _futureBuilder<R>(R Function() callback) async{
    return await compute<void,R>((_)async{
      return callback.call();
    }, null);
  }

  static Future<int> getTotalPhysicalMemory (){
    return _futureBuilder<int>(()=>s.SysInfo.getTotalPhysicalMemory());
  }

  static Future<int> getAvailablePhysicalMemory (){
    return _futureBuilder<int>(()=>s.SysInfo.getAvailablePhysicalMemory());
  }

}