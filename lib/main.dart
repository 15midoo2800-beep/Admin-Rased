# Admin-Rasd
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() => runApp(const RasedAdminApp());

class RasedAdminApp extends StatelessWidget {
  const RasedAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B132B),
        primaryColor: const Color(0xFF06D6A0),
      ),
      home: const AdminDashboardScreen(),
    );
  }
}

// محرك التشفير الخاص بتوليد الأكواد المرتبطة بمعرف الجهاز
class LicenseCrypto {
  static const String _secretSalt = "RASED_PRO_2026_SECRET_KEY";

  static String generateActivationCode(String deviceId, DateTime expiryDate) {
    String cleanDevice = deviceId.trim().toUpperCase();
    String expStr = "${expiryDate.year.toString().padLeft(4, '0')}${expiryDate.month.toString().padLeft(2, '0')}${expiryDate.day.toString().padLeft(2, '0')}";
    String raw = "$cleanDevice|$expStr|$_secretSalt";

    int hash = 0;
    for (int i = 0; i < raw.length; i++) {
      hash = ((hash << 5) - hash) + raw.codeUnitAt(i);
      hash &= 0xFFFFFFFF;
    }
    String sig = hash.toRadixString(16).toUpperCase().padLeft(8, '0');
    String payload = base64Url.encode(utf8.encode("$cleanDevice|$expStr|$sig")).replaceAll('=', '');
    return "ACT-$payload";
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final TextEditingController _clientNameCtrl = TextEditingController();
  final TextEditingController _deviceIdCtrl = TextEditingController();
  final TextEditingController _daysCtrl = TextEditingController(text: '30');

  // إعدادات الربط السحابي عبر GitHub للتحكم عن بُعد في إيقاف وتمديد العملاء
  final TextEditingController _ghTokenCtrl = TextEditingController();
  final TextEditingController _ghRepoCtrl = TextEditingController(); // مثال: username/rased-repo

  List<Map<String, dynamic>> _clients = [];
  String? _fileSha;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadAdminSettings();
  }

  Future<void> _loadAdminSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ghTokenCtrl.text = prefs.getString('gh_token') ?? '';
      _ghRepoCtrl.text = prefs.getString('gh_repo') ?? '';
      String? savedClients = prefs.getString('local_clients');
      if (savedClients != null) {
        _clients = List<Map<String, dynamic>>.from(json.decode(savedClients));
      }
    });
    if (_ghTokenCtrl.text.isNotEmpty && _ghRepoCtrl.text.isNotEmpty) {
      _fetchCloudClients();
    }
  }

  Future<void> _saveLocalClients() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('gh_token', _ghTokenCtrl.text.trim());
    prefs.setString('gh_repo', _ghRepoCtrl.text.trim());
    prefs.setString('local_clients', json.encode(_clients));
  }

  // جلب قائمة العملاء من GitHub
  Future<void> _fetchCloudClients() async {
    if (_ghTokenCtrl.text.isEmpty || _ghRepoCtrl.text.isEmpty) return;
    setState(() => _isSyncing = true);

    try {
      final url = Uri.parse('https://api.github.com/repos/${_ghRepoCtrl.text.trim()}/contents/clients_control.json');
      final res = await http.get(url, headers: {
        'Authorization': 'Bearer ${_ghTokenCtrl.text.trim()}',
        'Accept': 'application/vnd.github.v3+json',
      });

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        _fileSha = data['sha'];
        String content = utf8.decode(base64.decode(data['content'].toString().replaceAll('\n', '')));
        setState(() {
          _clients = List<Map<String, dynamic>>.from(json.decode(content));
        });
        _saveLocalClients();
      }
    } catch (_) {}
    setState(() => _isSyncing = false);
  }

  // رفع التعديلات (إيقاف عميل أو تمديد اشتراكه) إلى السحابة فوراً
  Future<void> _syncToCloud() async {
    await _saveLocalClients();
    if (_ghTokenCtrl.text.isEmpty || _ghRepoCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم الحفظ محلياً (أدخل إعدادات GitHub للمزامنة السحابية)', textDirection: TextDirection.rtl)),
      );
      return;
    }

    setState(() => _isSyncing = true);
    try {
      final url = Uri.parse('https://api.github.com/repos/${_ghRepoCtrl.text.trim()}/contents/clients_control.json');

      // جلب آخر SHA إذا لم يكن موجوداً
      if (_fileSha == null) {
        final getRes = await http.get(url, headers: {'Authorization': 'Bearer ${_ghTokenCtrl.text.trim()}'});
        if (getRes.statusCode == 200) {
          _fileSha = json.decode(getRes.body)['sha'];
        }
      }

      String jsonContent = json.encode(_clients);
      Map<String, dynamic> body = {
        'message': 'Update RASED Clients Control',
        'content': base64.encode(utf8.encode(jsonContent)),
      };
      if (_fileSha != null) body['sha'] = _fileSha;

      final putRes = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer ${_ghTokenCtrl.text.trim()}',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (putRes.statusCode == 200 || putRes.statusCode == 201) {
        _fileSha = json.decode(putRes.body)['content']['sha'];
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تحديث حالة العملاء عن بُعد بنجاح ✓', textDirection: TextDirection.rtl), backgroundColor: Color(0xFF06D6A0)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في المزامنة: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
    setState(() => _isSyncing = false);
  }

  void _createNewClientLicense() {
    String name = _clientNameCtrl.text.trim();
    String devId = _deviceIdCtrl.text.trim().toUpperCase();
    int days = int.tryParse(_daysCtrl.text.trim()) ?? 30;

    if (name.isEmpty || devId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم العميل ومعرف جهازه (Device ID)', textDirection: TextDirection.rtl), backgroundColor: Colors.redAccent),
      );
      return;
    }

    DateTime expiry = DateTime.now().add(Duration(days: days));
    String code = LicenseCrypto.generateActivationCode(devId, expiry);
    String expFormatted = "${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}";

    setState(() {
      _clients.removeWhere((c) => c['deviceId'] == devId);
      _clients.insert(0, {
        'name': name,
        'deviceId': devId,
        'expiry': expFormatted,
        'isActive': true,
        'code': code,
      });
    });

    _clientNameCtrl.clear();
    _deviceIdCtrl.clear();
    _syncToCloud();

    _showGeneratedCodeModal(name, devId, expFormatted, code);
  }

  void _showGeneratedCodeModal(String name, String devId, String expiry, String code) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF06D6A0))),
        title: const Text('تم توليد كود التفعيل بنجاح', style: TextStyle(color: Color(0xFF06D6A0)), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('العميل: $name', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text('معرف الجهاز: $devId', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            Text('ينتهي في: $expiry', style: const TextStyle(color: Colors.amber, fontSize: 12)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF0B132B), borderRadius: BorderRadius.circular(8)),
              child: SelectableText(code, style: const TextStyle(color: Color(0xFF06D6A0), fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF06D6A0)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ الكود لإرساله للعميل عبر واتساب', textDirection: TextDirection.rtl)),
              );
            },
            icon: const Icon(Icons.copy, color: Colors.black),
            label: const Text('نسخ الكود', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _extendClientDays(int index, int extraDays) {
    var client = _clients[index];
    DateTime currentExp = DateTime.tryParse(client['expiry']) ?? DateTime.now();
    if (currentExp.isBefore(DateTime.now())) currentExp = DateTime.now();

    DateTime newExp = currentExp.add(Duration(days: extraDays));
    String expFormatted = "${newExp.year}-${newExp.month.toString().padLeft(2, '0')}-${newExp.day.toString().padLeft(2, '0')}";
    String newCode = LicenseCrypto.generateActivationCode(client['deviceId'], newExp);

    setState(() {
      client['expiry'] = expFormatted;
      client['code'] = newCode;
      client['isActive'] = true;
    });

    _syncToCloud();
  }

  void _showCloudConfigDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        title: const Text('إعدادات التحكم عن بُعد (GitHub)', style: TextStyle(color: Color(0xFF06D6A0), fontSize: 15), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ghRepoCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(labelText: 'اسم المستودع (مثال: user/rased)', labelStyle: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ghTokenCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(labelText: 'GitHub Token (ghp_...)', labelStyle: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF06D6A0)),
            onPressed: () {
              _saveLocalClients();
              Navigator.pop(context);
              _fetchCloudClients();
            },
            child: const Text('حفظ ومزامنة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2541),
        title: const Text('RASED ADMIN - إدارة الاشتراكات', style: TextStyle(color: Color(0xFF06D6A0), fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_isSyncing)
            const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06D6A0)))),
          IconButton(icon: const Icon(Icons.cloud_sync, color: Color(0xFF06D6A0)), onPressed: _showCloudConfigDialog),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // بطاقة توليد كود جديد
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF1C2541), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('إنشاء كود تفعيل لعميل جديد', style: TextStyle(color: Color(0xFF06D6A0), fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _deviceIdCtrl,
                          decoration: const InputDecoration(hintText: 'معرف الجهاز (RSD-...)', hintStyle: TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _clientNameCtrl,
                          textDirection: TextDirection.rtl,
                          decoration: const InputDecoration(hintText: 'اسم العميل', hintStyle: TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF06D6A0), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                        onPressed: _createNewClientLicense,
                        icon: const Icon(Icons.vpn_key, color: Colors.black, size: 18),
                        label: const Text('توليد الكود وتفعيله', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _daysCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(labelText: 'المدة بالأيام', labelStyle: TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF06D6A0)), onPressed: _fetchCloudClients),
                Text('قائمة العملاء والتحكم (${_clients.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            // قائمة العملاء للتحكم في إيقافهم أو تمديد اشتراكهم
            Expanded(
              child: _clients.isEmpty
                  ? const Center(child: Text('لا يوجد عملاء مسجلين بعد', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _clients.length,
                      itemBuilder: (context, index) {
                        final c = _clients[index];
                        bool active = c['isActive'] ?? true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: active ? const Color(0xFF1C2541) : Colors.redAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: active ? const Color(0xFF06D6A0).withOpacity(0.4) : Colors.redAccent),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // زر إيقاف / تشغيل التطبيق لدى العميل
                                  Switch(
                                    value: active,
                                    activeColor: const Color(0xFF06D6A0),
                                    inactiveThumbColor: Colors.red,
                                    onChanged: (val) {
                                      setState(() => c['isActive'] = val);
                                      _syncToCloud();
                                    },
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(c['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                      Text('الجهاز: ${c['deviceId']} | ينتهي: ${c['expiry']}', style: const TextStyle(color: Colors.amber, fontSize: 11)),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    onPressed: () {
                                      setState(() => _clients.removeAt(index));
                                      _syncToCloud();
                                    },
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: c['code'] ?? ''));
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ كود العميل')));
                                    },
                                    icon: const Icon(Icons.copy, size: 15, color: Color(0xFF06D6A0)),
                                    label: const Text('نسخ الكود', style: TextStyle(color: Color(0xFF06D6A0), fontSize: 12)),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _extendClientDays(index, 30),
                                    child: const Text('+30 يوم', style: TextStyle(color: Colors.white, fontSize: 11)),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _extendClientDays(index, 7),
                                    child: const Text('+7 أيام', style: TextStyle(color: Colors.white, fontSize: 11)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
