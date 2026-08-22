class ResponseStruct {
  String? msg;
  dynamic data;
  int? status = 0;
  String? networkMsg;
  int totalPages;
  int currentPage;
  int perPage;

  ResponseStruct({
    this.msg,
    this.data,
    this.status,
    this.currentPage = 1,
    this.networkMsg,
    this.perPage = 0,
    this.totalPages = 1,
  });

  factory ResponseStruct.fromJson(Map<String, dynamic> parsedJson) {
    ResponseStruct res = ResponseStruct();
    res.msg = parsedJson["msg"];
    res.data = parsedJson["data"];
    res.status = parsedJson["status_code"] ?? 0;
    res.currentPage = parsedJson["current_page"] ?? 1;
    res.perPage = parsedJson["per_page"] ?? 1;
    res.totalPages = parsedJson["total_pages"] ?? 1;
    return res;
  }
}
