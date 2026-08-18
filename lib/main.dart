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
  int _filesCount = 0;
  late Directory _uploadDir;

  @override
  void initState() {
    super.initState();
    _bootServer();
  }

  Future<void> _bootServer() async {
    try {
      _uploadDir = await Directory.systemTemp.createTemp('fastdrop_vault_');
      
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

  // التعرف على الأنواع الحقيقية للملفات
  ContentType _getContentType(String filename) {
    String ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4': return ContentType('video', 'mp4');
      case 'mkv': return ContentType('video', 'x-matroska');
      case 'mp3': return ContentType('audio', 'mpeg');
      case 'jpg':
      case 'jpeg': return ContentType('image', 'jpeg');
      case 'png': return ContentType('image', 'png');
      case 'gif': return ContentType('image', 'gif');
      case 'pdf': return ContentType('application', 'pdf');
      case 'apk': return ContentType('application', 'vnd.android.package-archive');
      case 'zip': return ContentType('application', 'zip');
      case 'rar': return ContentType('application', 'x-rar-compressed');
      case '7z': return ContentType('application', 'x-7z-compressed');
      case 'doc':
      case 'docx': return ContentType('application', 'msword');
      default: return ContentType('application', 'octet-stream'); // النوع الثنائي الافتراضي
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    try {
      if (request.uri.path == '/') {
        String htmlContent = await rootBundle.loadString('assets/index.html');
        response.headers.contentType = ContentType.html;
        response.write(htmlContent);
      } 
      else if (request.uri.path == '/api/upload' && request.method == 'POST') {
        // queryParameters تقوم بفك التشفير تلقائياً، لا داعي لـ decodeComponent التي كانت تخرب الاسم
        String fileName = request.uri.queryParameters['name'] ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
        
        File newFile = File('${_uploadDir.path}/$fileName');
        var sink = newFile.openWrite(mode: FileMode.write);
        
        // الطريقة الفعلية والحقيقية للنقل (Chunk-by-Chunk Byte Transfer)
        // لا نستخدم cast أو addStream، بل نأخذ بايتات الشبكة ونكتبها مباشرة في القرص
        await for (var chunk in request) {
          sink.add(chunk);
        }
        
        await sink.flush(); // التأكد من كتابة كل البايتات للقرص
        await sink.close();
        
        _updateFilesCount();
        
        response.statusCode = HttpStatus.ok;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({"status": "success"}));
      } 
      else if (request.uri.path == '/api/files' && request.method == 'GET') {
        List<Map<String, dynamic>> fileData = [];
        if (_uploadDir.existsSync()) {
          for (var entity in _uploadDir.listSync()) {
            if (entity is File) {
              fileData.add({
                "name": entity.uri.pathSegments.last,
                "size": await entity.length(),
              });
            }
          }
        }
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(fileData));
      } 
      else if (request.uri.path == '/api/download') {
        String fileName = request.uri.queryParameters['file'] ?? '';
        File file = File('${_uploadDir.path}/$fileName');
        
        if (await file.exists()) {
          int fileSize = await file.length();
          String encodedName = Uri.encodeComponent(fileName);
          
          response.headers.contentType = _getContentType(fileName);
          response.headers.set('Content-Disposition', 'attachment; filename*=UTF-8\'\'$encodedName');
          response.headers.set('Content-Length', fileSize.toString());
          
          // البث المباشر للملف من القرص إلى الشبكة كـ Chunks
          await for (var chunk in file.openRead()) {
            response.add(chunk);
          }
          await response.close();
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

  void _updateFilesCount() {
    if (_uploadDir.existsSync()) {
      setState(() {
        _filesCount = _uploadDir.listSync().whereType<File>().length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Container(
          width: 550,
          padding: const EdgeInsets.all(35),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 25)],
            border: Border.all(color: const Color(0xFF38BDF8), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 75, color: Color(0xFF38BDF8)),
              const SizedBox(height: 15),
              const Text('سيرفر FastDrop يعمل الآن', style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 25),
              
              const Text('رابط هذا الجهاز:', style: TextStyle(color: Colors.grey, fontSize: 15)),
              const SizedBox(height: 4),
              SelectableText(_localUrl, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
              
              const SizedBox(height: 20),
              
              const Text('رابط الأجهزة الأخرى:', style: TextStyle(color: Colors.grey, fontSize: 15)),
              const SizedBox(height: 4),
              SelectableText(_networkUrl, style: const TextStyle(fontSize: 24, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
              
              const SizedBox(height: 25),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 18),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                child: Text('الملفات المستضافة: $_filesCount', style: const TextStyle(color: Colors.white70, fontSize: 16)),
              )
            ],
          ),
        ),
      ),
    );
  }
}
