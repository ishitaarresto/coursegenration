import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/models.dart';
import '../api/course_service.dart';
import '../api/document_service.dart';

final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<LibraryItem>>(LibraryNotifier.new);

class LibraryNotifier extends AsyncNotifier<List<LibraryItem>> {
  @override
  Future<List<LibraryItem>> build() => CourseService.listLibrary();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(CourseService.listLibrary);
  }

  Future<void> delete(String scriptId) async {
    await CourseService.deleteScript(scriptId);
    await refresh();
  }
}

final documentsProvider = AsyncNotifierProvider<DocumentsNotifier, List<DocumentInfo>>(DocumentsNotifier.new);

class DocumentsNotifier extends AsyncNotifier<List<DocumentInfo>> {
  @override
  Future<List<DocumentInfo>> build() => DocumentService.listDocuments();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(DocumentService.listDocuments);
  }
}
