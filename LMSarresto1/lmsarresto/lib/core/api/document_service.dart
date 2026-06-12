import 'api_client.dart';
import 'models.dart';

class DocumentService {
  static Future<List<DocumentInfo>> listDocuments() async {
    final data = await ApiClient.get('/api/v1/documents');
    final docs = (data as Map<String, dynamic>)['documents'] as List? ?? [];
    return docs.map((d) => DocumentInfo.fromJson(d as Map<String, dynamic>)).toList();
  }

  static Future<Map<String, dynamic>> uploadDocument(
      List<int> bytes, String filename) async {
    final data = await ApiClient.postMultipart(
      '/api/v1/documents/upload',
      {},
      fileField: 'file',
      fileBytes: bytes,
      filename: filename,
    );
    return data as Map<String, dynamic>;
  }

  static Future<void> deleteDocument(String sourceFile) async {
    final encoded = Uri.encodeComponent(sourceFile);
    await ApiClient.delete('/api/v1/documents/$encoded');
  }
}
