import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const MaterialApp(
      home: ElTorreonApp(),
      debugShowCheckedModeBanner: false,
    ));

class ElTorreonApp extends StatefulWidget {
  const ElTorreonApp({super.key});
  @override
  State<ElTorreonApp> createState() => _ElTorreonAppState();
}

class _ElTorreonAppState extends State<ElTorreonApp> {
  List<dynamic> _productos = [];
  List<dynamic> _filtrados = [];
  final TextEditingController _searchController = TextEditingController();

  final List<String> _headersOficiales = [
    'CODIGO interno',
    'Codigo de barras',
    'DESCRIPCION',
    'MARCA',
    'PRECIO MAYORISTA (\$)',
    'PRECIO MINORISTA (\$)',
    'PROVEEDOR'
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatosDeMemoria();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  Future<void> _cargarDatosDeMemoria() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('lista_precios');
    if (data != null) {
      setState(() { _productos = json.decode(data); });
    }
  }

  Future<void> _guardarEnMemoria() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lista_precios', json.encode(_productos));
  }

  Future<void> _exportarDatos() async {
    if (_productos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay datos para exportar")));
      return;
    }
    try {
      String csvData = _headersOficiales.join(";") + "\n";
      for (var p in _productos) {
        csvData += _headersOficiales.map((h) => p[h]?.toString() ?? "").join(";") + "\n";
      }
      final Directory directory = await getTemporaryDirectory();
      final String filePath = '${directory.path}/Lista_Precios_Torreon.csv';
      final File file = File(filePath);
      await file.writeAsString(csvData, encoding: utf8);
      await Share.shareXFiles([XFile(filePath)], text: 'Copia de seguridad El Torreón');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error al exportar: $e")));
    }
  }

  Future<void> _importarArchivo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
    );

    if (result != null) {
      File file = File(result.files.single.path!);
      List<dynamic> nuevaLista = [];
      try {
        if (result.files.single.extension == 'csv') {
          final input = file.readAsBytesSync();
          final decoded = utf8.decode(input, allowMalformed: true);
          List<String> lineas = const LineSplitter().convert(decoded);
          if (lineas.isNotEmpty) {
            String separador = lineas[0].contains(';') ? ';' : ',';
            for (var i = 1; i < lineas.length; i++) {
              List<String> values = lineas[i].split(separador);
              var map = {};
              for (var j = 0; j < _headersOficiales.length; j++) {
                map[_headersOficiales[j]] = j < values.length ? values[j].trim() : "";
              }
              nuevaLista.add(map);
            }
          }
        } else {
          var bytes = file.readAsBytesSync();
          var excel = Excel.decodeBytes(bytes);
          var table = excel.tables[excel.tables.keys.first];
          for (var i = 1; i < (table?.maxRows ?? 0); i++) {
            var row = table?.rows[i];
            var map = {};
            for (var j = 0; j < _headersOficiales.length; j++) {
              map[_headersOficiales[j]] = row?[j]?.value.toString() ?? "";
            }
            nuevaLista.add(map);
          }
        }
        setState(() {
          _productos = nuevaLista;
          _filtrados = [];
          _searchController.clear();
        });
        _guardarEnMemoria();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lista cargada con éxito")));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error al leer archivo")));
      }
    }
  }

  void _buscar(String consulta) {
    setState(() {
      if (consulta.isEmpty) {
        _filtrados = [];
      } else {
        _filtrados = _productos.where((p) {
          final desc = p['DESCRIPCION']?.toString().toLowerCase() ?? '';
          final marca = p['MARCA']?.toString().toLowerCase() ?? '';
          final barras = p['Codigo de barras']?.toString().toLowerCase() ?? '';
          final query = consulta.toLowerCase();
          return desc.contains(query) || marca.contains(query) || barras.contains(query);
        }).toList();
      }
    });
  }

  void _mostrarFormularioProducto({Map<String, dynamic>? productoExistente, int? index}) {
    String proximoID = "";
    if (productoExistente == null) {
      int max = 0;
      for (var p in _productos) {
        int val = int.tryParse(p['CODIGO interno']?.toString() ?? "0") ?? 0;
        if (val > max) max = val;
      }
      proximoID = (max + 1).toString();
    }

    Map<String, TextEditingController> controladores = {};
    for (var h in _headersOficiales) {
      String inicial = productoExistente != null 
          ? productoExistente[h]?.toString() ?? "" 
          : (h == 'CODIGO interno' ? proximoID : "");
      controladores[h] = TextEditingController(text: inicial);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(productoExistente == null ? "Nuevo Producto" : "Editar Producto"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ..._headersOficiales.map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(
                  controller: controladores[h],
                  enabled: true, 
                  decoration: InputDecoration(
                    labelText: h, 
                    border: const OutlineInputBorder(),
                    suffixIcon: h == 'Codigo de barras' 
                      ? IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: () => _escanearParaFormulario(controladores[h]!))
                      : null,
                  ),
                ),
              )).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                Map<String, dynamic> nuevo = {};
                controladores.forEach((key, ctrl) => nuevo[key] = ctrl.text);
                if (index == null) { _productos.add(nuevo); } else { _productos[index] = nuevo; }
                _buscar(_searchController.text);
              });
              _guardarEnMemoria();
              Navigator.pop(context);
            },
            child: const Text("Guardar"),
          )
        ],
      ),
    );
  }

  void _mostrarOpciones(dynamic producto) {
    int idx = _productos.indexOf(producto);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Editar datos"),
              onTap: () { Navigator.pop(context); _mostrarFormularioProducto(productoExistente: producto, index: idx); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Eliminar producto"),
              onTap: () {
                Navigator.pop(context);
                setState(() { _productos.removeAt(idx); _buscar(_searchController.text); });
                _guardarEnMemoria();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _escanearParaFormulario(TextEditingController controller) async {
    final String? codigoEscaneado = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PantallaEscaneo()),
    );

    if (codigoEscaneado != null && codigoEscaneado.isNotEmpty) {
      setState(() {
        controller.text = codigoEscaneado;
      });
      _buscar(codigoEscaneado);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('El Torreón - Precios'),
        backgroundColor: const Color(0xFF1F2937),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: _exportarDatos),
          IconButton(icon: const Icon(Icons.file_open), onPressed: _importarArchivo),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _buscar,
                    decoration: InputDecoration(
                      hintText: 'Buscar...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _buscar("");
                            },
                          ) 
                        : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () => _escanearParaFormulario(_searchController),
                  style: IconButton.styleFrom(backgroundColor: Colors.blue),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtrados.length,
              itemBuilder: (context, index) {
                final p = _filtrados[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: ListTile(
                    title: Text("${p['DESCRIPCION']} - ${p['MARCA']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Int: ${p['CODIGO interno']} | Barras: ${p['Codigo de barras']}"),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("\$ ${p['PRECIO MINORISTA (\$)']}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text("May: \$ ${p['PRECIO MAYORISTA (\$)']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    onTap: () => _mostrarOpciones(p),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarFormularioProducto(),
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class PantallaEscaneo extends StatefulWidget {
  const PantallaEscaneo({super.key});

  @override
  State<PantallaEscaneo> createState() => _PantallaEscaneoState();
}

class _PantallaEscaneoState extends State<PantallaEscaneo> {
  final MobileScannerController scannerController = MobileScannerController();

  @override
  void dispose() {
    scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Escanear Código"),
        backgroundColor: const Color(0xFF1F2937),
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        controller: scannerController,
        onDetect: (capture) {
          if (capture.barcodes.isNotEmpty) {
            final String? codigo = capture.barcodes.first.rawValue;
            if (codigo != null && codigo.isNotEmpty) {
              scannerController.stop(); // Apaga la cámara antes de volver
              Navigator.pop(context, codigo); // Cierra y devuelve el código
            }
          }
        },
      ),
    );
  }
}