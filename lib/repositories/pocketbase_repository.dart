import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';
import "package:http/http.dart" as http;

import '../models/pocketbase_model.dart';
import '../provider/pocketbase_provider.dart';

typedef JsonMap = Map<String, dynamic>;

class JsonConverter {
  static JsonMap toRecordModelJson(
    BaseModel model, {
    List<String>? relations,
  }) {
    var json = model.toJson();
    json.removeWhere((key, value) => key == null || value == null);
    for (final relation in relations ?? []) {
      final relKey = json[relation];
      if (relKey is BaseModel) {
        json[relation] = json[relation].id;
      }
      // TODO untested
      if (relKey is List<BaseModel>) {
        json[relation] = (json[relation] as List<BaseModel>)
            .map((BaseModel i) => i.id)
            .toList();
      }
    }
    return json;
  }

  static JsonMap toBaseModelJson(
    RecordModel model, {
    List<String>? relations,
  }) {
    var json = model.toJson();
    json.removeWhere((key, value) => key == null || value == null);
    if (json.containsKey("expand") && (json['expand'] as Map).isNotEmpty) {
      (json['expand'] as Map).forEach((field, data) => json[field] = data);
      json.remove("expand");
    } else {
      for (final relation in relations ?? []) {
        if ((json[relation] as String).isEmpty) {
          json.remove(relation);
        }
      }
    }
    return json;
  }
}

final collectionServiceProvider = Provider.family<RecordService, String>(
    (ref, collection) => ref.watch(pocketBaseProvider).collection(collection));

abstract class PocketbaseRepository<T extends BaseModel>
    extends StateNotifier<AsyncValue<List<T>>> {
  final RecordService recordService;
  List<String>? relations;

  PocketbaseRepository(this.recordService) : super(const AsyncData([]));

  Future<void> getAll({bool loading = false});

  Future<Iterable> getAsMap({
    int batch = 200,
    String? filter,
    String? sort,
    Map<String, dynamic> query = const {},
    Map<String, String> headers = const {},
  }) async {
    final data = await recordService.getFullList(
      expand: relations?.join(","),
      filter: filter,
      sort: sort,
      query: query,
      headers: headers,
    );
    return data
        .map((rm) => JsonConverter.toBaseModelJson(rm, relations: relations));
  }

  Future<AsyncValue<RecordModel>> create(T model, { List<http.MultipartFile> files = const [] }) async {
    /// Returns an error string, null for success
    ///
    // final state = await AsyncValue.guard(() => {
    //       recordService.create(
    //         body: JsonConverter.toRecordModelJson(model, relations: relations),
    //       )
    //     });
    try {
      final rm = await recordService.create(
        body: JsonConverter.toRecordModelJson(model, relations: relations),
        files: files,
      );
      getAll(loading: false);
      return AsyncData<RecordModel>(rm);
    } on ClientException catch (e) {
      return AsyncError<RecordModel>(
        "${e.response['message']}: ${e.response['data']}",
        StackTrace.current,
      );
      // return "${e.response['message']}: ${e.response['data']}";
    }
  }

  Future<AsyncValue<RecordModel>> update(T model, { List<http.MultipartFile> files = const [] }) async {
    try {
      final rm = await recordService.update(
        model.id!,
        body: JsonConverter.toRecordModelJson(model, relations: relations),
        files: files,
      );
      getAll(loading: false);
      return AsyncData<RecordModel>(rm);
    } on ClientException catch (e) {
      return AsyncError<RecordModel>(
        "${e.response['message']}: ${e.response['data']}",
        StackTrace.current,
      );
    }
  }

  Future<void> delete(String id) async {
    await recordService.delete(id);
    getAll(loading: false);
  }
}
