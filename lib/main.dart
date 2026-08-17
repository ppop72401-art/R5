import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() => runApp(const FastDropApp());

class FastDropApp extends StatelessWidget {
  const FastDropApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false, 
      home: ServerDashboard()
    );
  }
}

class ServerDashboard extends StatefulWidget {
  const ServerDashboard({super.key});
  @override
  State<ServerDashboard> createState() => _ServerDashboardState();
}

class _ServerDashboardState extends State<ServerDashboard> {
  HttpServer? _server;
  String _localUrl = "جاري التهيئة...";
  String _networkUrl = "جاري التهيئة...";
  int _port = 8080;
  List<String> _uploadedFiles = [];
  late Directory _uploadDir;

  @override
  void initState() {
    super.initState();
    _bootServer();
  }

  Future<void> _bootServer() async {
    try {
      // تجهيز مجلد لحفظ الملفات
      _uploadDir = await Directory.systemTemp.createTemp('fastdrop_vault_');
      
      // جلب عنوان الـ IP للشبكة المحلية (Wi-Fi)
      List<String> ips = [];
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) ips.add(addr.address);
        }
      }
      
      String networkIp = ips.isNotEmpty ? ips.first : 'غير متصل بشبكة';
      
      setState(() {
        _localUrl = "http://127.0.0.1:$_port";
        _networkUrl = ips.isNotEmpty ? "http://$networkIp:$_port" : "الرجاء الاتصال بالـ Wi-Fi";
      });

      // إطلاق السيرفر
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _listenToRequests();
      
    } catch (e) {
      setState(() {
        _networkUrl = "🔴 فشل إقلاع السيرفر: $e";
      });
    }
  }

  void _listenToRequests() async {
    await for (HttpRequest request in _server!) {
      _handleRequest(request);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    
    // حل مشاكل الـ CORS لضمان اتصال الأجهزة الأخرى
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, X-File-Name');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    try {
      if (request.uri.path == '/') {
        // تحميل وعرض واجهة الـ HTML
        String htmlContent = await rootBundle.loadString('assets/index.html');
        response.headers.contentType = ContentType.html;
        response.write(htmlContent);
      } 
      else if (request.uri.path == '/api/upload' && request.method == 'POST') {
        // استقبال تيار الملف السريع
        String fileName = request.headers.value('X-File-Name') ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
        fileName = Uri.decodeComponent(fileName);
        
        File newFile = File('${_uploadDir.path}/$fileName');
        var sink = newFile.openWrite();
        
        // ----------------------------------------------------
        // الإصلاح هنا: استخدام addStream بدلاً من pipe
        // ----------------------------------------------------
        await sink.addStream(request);
        await sink.close();
        
        _updateFilesList();
        
        response.statusCode = HttpStatus.ok;
        response.write(jsonEncode({"status": "success"}));
      } 
      else if (request.uri.path == '/api/files' && request.method == 'GET') {
        // إرسال قائمة الملفات المتاحة
        _updateFilesList();
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(_uploadedFiles));
      } 
      else if (request.uri.path.startsWith('/api/download/')) {
        // تحميل الملف المطلوب
        String fileName = Uri.decodeComponent(request.uri.pathSegments.last);
        File file = File('${_uploadDir.path}/$fileName');
        
        if (await file.exists()) {
          response.headers.contentType = ContentType.binary;
          response.headers.add('Content-Disposition', 'attachment; filename="$fileName"');
          response.contentLength = await file.length();
          await file.openRead().pipe(response);
          return; 
        } else {
          response.statusCode = HttpStatus.notFound;
        }
      } 
      else {
        response.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
    }
    await response.close();
  }

  void _updateFilesList() {
    if (_uploadDir.existsSync()) {
      final List<FileSystemEntity> entities = _uploadDir.listSync();
      setState(() {
        _uploadedFiles = entities.whereType<File>().map((f) => f.uri.pathSegments.last).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30)],
            border: Border.all(color: const Color(0xFF38BDF8), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.rocket_launch, size: 80, color: Color(0xFF38BDF8)),
              const SizedBox(height: 20),
              const Text('خادم النقل يعمل بنجاح 🟢', style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              
              const Text('رابط هذا الجهاز (للمضيف):', style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 5),
              SelectableText(_localUrl, style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
              
              const SizedBox(height: 25),
              
              const Text('رابط الشبكة (للأجهزة الأخرى):', style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 5),
              SelectableText(_networkUrl, style: const TextStyle(fontSize: 26, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
              
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(15)),
                child: Text('الملفات في الخادم: ${_uploadedFiles.length}', style: const TextStyle(color: Colors.white70, fontSize: 18)),
              )
            ],
          ),
        ),
      ),
    );
  }
}
