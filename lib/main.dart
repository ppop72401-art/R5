import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

void main() {
  runApp(const FastDropApp());
}

class FastDropApp extends StatelessWidget {
  const FastDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FastDrop Server',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8),
          brightness: Brightness.dark,
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const ServerDashboard(),
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
  String _serverIp = "جاري الاتصال...";
  int _port = 8080;
  List<String> _uploadedFiles = [];
  late Directory _uploadDir;

  @override
  void initState() {
    super.initState();
    _initServer();
  }

  Future<void> _initServer() async {
    try {
      // إنشاء مجلد التخزين المؤقت للملفات المرفوعة
      _uploadDir = await Directory.systemTemp.createTemp('fast_drop_');
      
      // الحصول على IP الشبكة المحلية
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      String ip = 'localhost';
      for (var interface in interfaces) {
        if (interface.name.contains('wlan') || interface.name.contains('en') || interface.name.contains('eth')) {
          ip = interface.addresses.first.address;
          break;
        }
      }

      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      
      setState(() {
        _serverIp = "http://$ip:$_port";
      });

      _listenToRequests();
    } catch (e) {
      setState(() {
        _serverIp = "خطأ في تشغيل السيرفر: $e";
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
    
    // إضافة ترويسات CORS للسماح بالاتصال من أي مكان
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
        // تقديم واجهة الويب HTML
        response.headers.contentType = ContentType.html;
        response.write(_getHtmlClient());
      } 
      else if (request.uri.path == '/api/upload' && request.method == 'POST') {
        // استقبال تيار البيانات الخام (Raw Stream) لسرعة قصوى
        String fileName = request.headers.value('X-File-Name') ?? 'unknown_file_${DateTime.now().millisecondsSinceEpoch}';
        fileName = Uri.decodeComponent(fileName);
        
        File newFile = File('${_uploadDir.path}/$fileName');
        var sink = newFile.openWrite();
        await request.pipe(sink);
        await sink.close();
        
        _updateFilesList();
        
        response.statusCode = HttpStatus.ok;
        response.write(jsonEncode({"status": "success", "message": "تم الرفع بسرعة البرق!"}));
      } 
      else if (request.uri.path == '/api/files' && request.method == 'GET') {
        // إرجاع قائمة الملفات
        _updateFilesList();
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(_uploadedFiles));
      } 
      else if (request.uri.path.startsWith('/api/download/')) {
        // تحميل الملف
        String fileName = Uri.decodeComponent(request.uri.pathSegments.last);
        File file = File('${_uploadDir.path}/$fileName');
        
        if (await file.exists()) {
          response.headers.contentType = ContentType.binary;
          response.headers.add('Content-Disposition', 'attachment; filename="$fileName"');
          response.contentLength = await file.length();
          await file.openRead().pipe(response);
          return; // Pipe يغلق الاتصال تلقائياً
        } else {
          response.statusCode = HttpStatus.notFound;
          response.write('File not found');
        }
      } 
      else {
        response.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
      response.write('Error: $e');
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
  void dispose() {
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مركبة النقل السريع 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_tethering, size: 80, color: Color(0xFF38BDF8)),
            const SizedBox(height: 20),
            const Text(
              'السيرفر يعمل الآن!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            const Text(
              'اطلب من الأجهزة الأخرى فتح هذا الرابط في المتصفح:',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFF38BDF8), width: 2),
              ),
              child: SelectableText(
                _serverIp,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              'الملفات المستضافة حالياً: ${_uploadedFiles.length}',
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // واجهة الويب (HTML/CSS/JS) المدمجة
  // ============================================================================
  String _getHtmlClient() {
    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FastDrop - نقل البيانات السريع</title>
    <link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@400;700;900&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #0f172a; --surface: #1e293b; --accent: #38bdf8; --text: #f8fafc;
        }
        * { box-sizing: border-box; font-family: 'Tajawal', sans-serif; margin: 0; padding: 0; }
        body { background-color: var(--bg); color: var(--text); padding: 20px; }
        
        .header { text-align: center; margin-bottom: 40px; }
        .header h1 { font-size: 2.5rem; color: var(--accent); }
        
        /* تصميم العمودين */
        .container {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 30px;
            max-width: 1200px;
            margin: 0 auto;
        }
        
        @media (max-width: 768px) {
            .container { grid-template-columns: 1fr; }
        }
        
        .panel {
            background: var(--surface);
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.5);
            border: 1px solid rgba(255,255,255,0.05);
        }
        
        .panel h2 { margin-bottom: 20px; border-bottom: 2px solid rgba(255,255,255,0.1); padding-bottom: 10px; }
        
        /* منطقة الرفع */
        .upload-area {
            border: 3px dashed var(--accent);
            border-radius: 15px;
            padding: 60px 20px;
            text-align: center;
            cursor: pointer;
            transition: 0.3s;
            background: rgba(56, 189, 248, 0.05);
        }
        .upload-area:hover { background: rgba(56, 189, 248, 0.1); transform: translateY(-5px); }
        .upload-area input { display: none; }
        .upload-area span { display: block; font-size: 1.5rem; font-weight: bold; color: var(--accent); margin-bottom: 10px;}
        
        /* شريط التقدم */
        #progress-container { width: 100%; height: 10px; background: rgba(255,255,255,0.1); border-radius: 5px; margin-top: 20px; display: none; overflow: hidden; }
        #progress-bar { height: 100%; width: 0%; background: var(--accent); transition: width 0.1s; }
        
        /* قائمة الملفات */
        .file-list { display: flex; flex-direction: column; gap: 15px; }
        .file-item {
            background: rgba(0,0,0,0.3);
            padding: 15px;
            border-radius: 12px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .file-name { font-weight: bold; word-break: break-all; margin-left: 15px; }
        
        /* أدوات التنزيل */
        .download-tools { display: flex; gap: 10px; align-items: center; }
        
        select {
            padding: 8px 12px;
            border-radius: 8px;
            background: var(--bg);
            color: var(--text);
            border: 1px solid var(--accent);
            outline: none;
            cursor: pointer;
        }
        
        .btn-download {
            background: var(--accent);
            color: var(--bg);
            text-decoration: none;
            padding: 8px 20px;
            border-radius: 8px;
            font-weight: bold;
            transition: 0.2s;
        }
        .btn-download:hover { transform: scale(1.05); box-shadow: 0 0 15px rgba(56,189,248,0.4); }
    </style>
</head>
<body>

    <div class="header">
        <h1>FastDrop 🚀</h1>
        <p>نقل بيانات فوري عبر الشبكة المحلية</p>
    </div>

    <div class="container">
        <!-- العمود الأول: الرفع -->
        <div class="panel">
            <h2>📤 إرسال ملف</h2>
            <label class="upload-area" id="drop-zone">
                <span>اضغط هنا أو اسحب الملف</span>
                <p>يدعم جميع أنواع الملفات بالأحجام الكبيرة</p>
                <input type="file" id="file-input" multiple>
            </label>
            
            <div id="progress-container">
                <div id="progress-bar"></div>
            </div>
            <p id="upload-status" style="text-align: center; margin-top: 10px; color: var(--accent);"></p>
        </div>

        <!-- العمود الثاني: التنزيل -->
        <div class="panel">
            <h2>📥 الملفات المتاحة</h2>
            <div class="file-list" id="file-list">
                <!-- سيتم ملء القائمة عبر الجافاسكربت -->
            </div>
        </div>
    </div>

    <script>
        const fileInput = document.getElementById('file-input');
        const fileList = document.getElementById('file-list');
        const progressBar = document.getElementById('progress-bar');
        const progressContainer = document.getElementById('progress-container');
        const uploadStatus = document.getElementById('upload-status');

        // جلب قائمة الملفات
        async function fetchFiles() {
            try {
                const response = await fetch('/api/files');
                const files = await response.json();
                
                fileList.innerHTML = '';
                if(files.length === 0) {
                    fileList.innerHTML = '<p style="text-align:center; color:gray;">لا توجد ملفات مرفوعة بعد.</p>';
                    return;
                }

                files.forEach(file => {
                    const decodedName = decodeURIComponent(file);
                    // تصميم عنصر الملف
                    const item = document.createElement('div');
                    item.className = 'file-item';
                    
                    item.innerHTML = `
                        <div class="file-name">\${decodedName}</div>
                        <div class="download-tools">
                            <select title="تحديد الجودة (يتم نقل الملف الأصلي لضمان أقصى سرعة)">
                                <option value="original">الدقة الأصلية (أسرع نقل)</option>
                            </select>
                            <a href="/api/download/\${encodeURIComponent(file)}" class="btn-download" download>تنزيل</a>
                        </div>
                    `;
                    fileList.appendChild(item);
                });
            } catch (e) {
                console.error("Error fetching files:", e);
            }
        }

        // معالجة الرفع العالي السرعة عبر XMLHttpRequest للحصول على نسبة التقدم اللحظية
        fileInput.addEventListener('change', (e) => {
            const files = e.target.files;
            if(files.length === 0) return;

            Array.from(files).forEach(file => {
                uploadFile(file);
            });
            fileInput.value = ''; // تصفير الإدخال
        });

        function uploadFile(file) {
            progressContainer.style.display = 'block';
            uploadStatus.innerText = `جاري رفع \${file.name}...`;
            
            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/api/upload', true);
            
            // تمرير اسم الملف في الترويسة للسرعة وتجاوز مشاكل الـ Multipart
            xhr.setRequestHeader('X-File-Name', encodeURIComponent(file.name));

            xhr.upload.onprogress = (event) => {
                if (event.lengthComputable) {
                    const percentComplete = (event.loaded / event.total) * 100;
                    progressBar.style.width = percentComplete + '%';
                }
            };

            xhr.onload = () => {
                if (xhr.status === 200) {
                    uploadStatus.innerText = 'تم الرفع بنجاح! ✔️';
                    setTimeout(() => { progressContainer.style.display = 'none'; progressBar.style.width = '0%'; uploadStatus.innerText = ''; }, 2000);
                    fetchFiles();
                } else {
                    uploadStatus.innerText = 'حدث خطأ أثناء الرفع ❌';
                    uploadStatus.style.color = 'red';
                }
            };

            // إرسال الملف كـ Raw Stream مباشرة
            xhr.send(file);
        }

        // تحديث القائمة تلقائياً كل 3 ثواني ليرى الجميع الملفات الجديدة
        setInterval(fetchFiles, 3000);
        fetchFiles();
    </script>
</body>
</html>
    ''';
  }
}
