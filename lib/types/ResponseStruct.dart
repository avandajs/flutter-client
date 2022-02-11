class ResponseStruct {
  String? msg;
  dynamic data;
  int? status = 0;
  String? networkMsg;
  int totalPages = 1;
  int currentPage = 1;

  ResponseStruct({this.msg,this.data,this.status,this.currentPage = 1,this.networkMsg,this.totalPages = 1});

  factory ResponseStruct.fromJson(Map<String, dynamic> parsedJson){
    ResponseStruct res = ResponseStruct();
    for(var key in parsedJson.keys){
      switch(key){
        case "msg":
          res.msg = parsedJson[key];
          break;
        case "data":
          res.data = parsedJson[key];
          break;
        case "status_code":
          res.status = parsedJson[key];
          break;
      }
    }
    return res;
  }
}
