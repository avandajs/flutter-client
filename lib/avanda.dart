library avanda;

import 'dart:convert';

import 'package:avanda/exceptions/Internal_server_error.dart';
import 'package:avanda/exceptions/access_forbidden_error.dart';
import 'package:avanda/exceptions/bad_request_error.dart';
import 'package:avanda/exceptions/file_not_found_error.dart';
import 'package:avanda/exceptions/internet_network_error.dart';
import 'package:avanda/exceptions/method_not_allowed_error.dart';
import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/exceptions/unauthorized_error.dart';
import 'package:avanda/exceptions/unknown_error.dart';
import 'package:avanda/response.dart';
import 'package:avanda/types/Query.dart';
import 'package:avanda/types/ResponseStruct.dart';
import 'package:avanda/types/Service.dart';
import 'package:http/http.dart' as http;
// import 'package:class_to_map/class_to_map.dart';

enum RequestMethods { get, delete, post }

class Avanda {
  static String endpoint = "/";

  Service queryTree = Service(ft: {}, c: [], p: 0, pr: {});
  static Map? requestConfig;
  static Map<String, String> headers = {};

  bool autoLink = true;

  dynamic lastCol;
  bool accumulate = false;

  Map? postData;

  static setGraphRoot(String root) {
    Avanda.endpoint = root;
  }

  static setRequestConfig(Map config) {
    Avanda.requestConfig = {
      ...(Avanda.requestConfig ?? {}),
      ...config,
    };
  }

  static column(String column) {
    RegExp pattern = RegExp(r'[^\w_]');
    if (pattern.hasMatch(column)) {
      throw "Invalid column name";
    }
    return column;
  }

  Future<dynamic> file(event) async {}

  static validColOnly(String column) {
    RegExp pattern = RegExp(r'!/[\w._]+/');
    if (pattern.hasMatch(column)) {
      throw "Invalid column name";
    }
    return column;
  }

  static col(String column) {
    return Avanda.column(column);
  }

  Avanda disableAutoLink() {
    autoLink = false;
    return this;
  }

  Avanda service(String name) {
    List tokens = name.split("/");
    queryTree.f = tokens.length > 1 ? tokens[1] : null;
    queryTree.n = tokens[0];
    return this;
  }

  Avanda where(dynamic conditions) {
    if (conditions is Map) {
      queryTree.ft = objToFilter(conditions);
    } else if (conditions is String) {
      lastCol = conditions;
    }
    return this;
  }

  Map objToFilter(Map obj) {
    Map filters = {};

    for (String k in obj.keys) {
      filters[k] = {'vl': obj[k], 'op': "="};
    }
    //
    return filters;
  }

  Avanda andWhere(dynamic conditions) {
    if (queryTree.n == null) {
      throw 'Specify service to apply where clause on';
    }

    if (conditions is Map) {
      queryTree.ft = {...queryTree.ft, ...conditions};
    } else if (conditions is String) {
      lastCol = conditions;
    }
    return this;
  }

  Avanda greaterThan(int value) {
    return addCustomFilter(value, ">");
  }

  Avanda lessThan(int value) {
    return addCustomFilter(value, "<");
  }

  Avanda equals(dynamic value) {
    return addCustomFilter(value, "==");
  }

  Avanda notEquals(dynamic value) {
    return addCustomFilter(value, "!=");
  }

  Avanda isNull() {
    return addCustomFilter(null, "NULL");
  }

  Avanda isNotNull() {
    return addCustomFilter(null, "NOTNULL");
  }

  Avanda isLike(dynamic value) {
    return addCustomFilter(value, "LIKES");
  }

  Avanda isNotLike(value) {
    return addCustomFilter(value, "NOT-LIKES");
  }

  Avanda addCustomFilter(dynamic value, String operator) {
    if (!lastCol) {
      throw "Specify column to compare $value with";
    }
    Map filter = {
      lastCol: {'vl': value, 'op': operator}
    };

    if (queryTree.n == null) {
      throw 'Specify service to apply where clauses';
    }

    queryTree.ft = {...(accumulate ? queryTree.ft : {}), ...filter};

    lastCol = null;
    accumulate = false;

    return this;
  }

  ref(int id) {
    queryTree.ft = {
      ...queryTree.ft,
      ...objToFilter({'id': id})
    };
    return this;
  }

  page(int page) {
    queryTree.p = page;
    return this;
  }

  search(String col, String keyword) {
    queryTree.q = Query(c: Avanda.validColOnly(col), k: keyword);

    return this;
  }

  select(List columns) {
    if (queryTree.n == null) {
      throw 'Specify service to select from';
    }
    queryTree.f = "get";
    fetch(columns);
    return this;
  }

  selectAll(List columns) {
    if (queryTree.n == null) {
      throw 'Specify service to select from';
    }
    queryTree.f = "getAll";
    fetch(columns);
    return this;
  }

  Avanda func(String func) {
    if (queryTree.n == null) {
      throw 'Specify service to select from';
    }
    queryTree.f = func;
    return this;
  }

  fetch(List columns) {
    if (queryTree.n == null) {
      throw "Specify service to fetch from";
    }

    queryTree.c = columns.map((column) {
      if (column is Avanda) {
        return column.queryTree;
      }
      return column is String ? Avanda.column(column) : column;
    }).toList();

    return this;
  }

  Service as(String alias) {
    if (queryTree.n == null) {
      throw 'Specify service to apply alias to';
    }
    queryTree.a = alias;
    return queryTree;
  }

  String toLink() {
    if (queryTree.n == null) {
      throw "Service not specified";
    }
    queryTree.al = autoLink;

    return jsonEncode(queryTree);
  }

  Future<Response> makeRequest(
      {endpoint, required RequestMethods method, params}) async {
    http.Response httpResponse;

    endpoint = Avanda.endpoint + '?query=' + endpoint;

    try{
      switch (method) {
        case RequestMethods.get:
          httpResponse = await http.get(Uri.parse(endpoint), headers: headers);
          break;
        case RequestMethods.post:
          httpResponse = await http.post(Uri.parse(endpoint),
              headers: headers, body: params);
          break;
        case RequestMethods.delete:
          httpResponse = await http.delete(Uri.parse(endpoint),
              headers: headers, body: params);
          break;
      }
    }catch(e){
      throw InternetNetworkError(ResponseStruct.fromJson({}));
    }

    var response = ResponseStruct.fromJson(jsonDecode(httpResponse.body));

    Map<int, RequestException> errors = {
      404: FileNotFoundError(response),
      400: BadRequestError(response),
      500: InternalServerError(response),
      403: AccessForbiddenError(response),
      401: UnauthorizedAccess(response),
      405: MethodNotAllowedError(response),
      0: InternetNetworkError(response),
    };

    if (errors.containsKey(response.status) && (response.status ?? 500) >= 300){
      throw errors[response.status] ?? UnknownError(response);
    }

    return Response(response);

// return new Promise(async (resolve, reject) => {
// try {
// let res = await (req as any)[method](endpoint, await params,Graph.requestConfig);
// res = res.data;
// resolve(new Response(res));
// } catch (e) {
// let err = e as (Error | AxiosError)
//
// let error: ResponseStruct = {
// currentPage: 0,
// data: undefined,
// msg: "",
// networkMsg: err?.message ?? "unknown",
// status: 0,
// totalPages: 0
// };
//
// let netRes: ResponseStruct
//
//
// if (axios.isAxiosError(err)){
// netRes =  (err.response as unknown as ResponseStruct)
// error.data = netRes?.data?.data
// error.msg = netRes?.data?.msg
// error.status = netRes?.status ?? netRes?.data?.statusCode
// error.totalPages = netRes?.data?.totalPages
// error.currentPage = netRes?.data?.currentPage
// }
//
// error.networkMsg = err.message
//
// reject(new Response(error));
// }
// });
  }

  Future<Response> get() async {
    var link = toLink();
    return await makeRequest(endpoint: link, method: RequestMethods.get);
  }

  Future<Response> post(Map values) async {
    return await set(values);
  }

  Future<Response> delete() async {
    var link = toLink();
    return await makeRequest(endpoint: link, method: RequestMethods.delete);
  }

  Future<Response> set(Map values) async {
    if (queryTree.n == null) {
      throw "Specify service to send request to";
    }
    postData = values;

    String link = toLink();

    return await makeRequest(
        endpoint: link, method: RequestMethods.post, params: postData);
  }

  Future<Response> update(values) async {
    if (queryTree.n == null) {
      throw 'Specify service to send request to';
    }

    postData = values;

    String link = toLink() + '&_method=PATCH';
    return await makeRequest(
        endpoint: link, method: RequestMethods.post, params: postData);
  }

  params(Map params) {
    if (queryTree.n == null) {
      throw 'Specify service to bind param to';
    }
    queryTree.pr = params;
    return this;
  }
}
