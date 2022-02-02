class ResponseStruct {
  String? msg;
  dynamic data;
  int? status = 0;
  String? networkMsg;
  int totalPages = 1;
  int currentPage = 1;

  ResponseStruct({this.msg,this.data,this.status,this.currentPage = 1,this.networkMsg,this.totalPages = 1});
}
