import 'package:avanda/types/ResponseStruct.dart';

class Response {
  ResponseStruct rawResponse = ResponseStruct();

  Response(this.rawResponse);

  getData<T>() {
    return rawResponse.data as T;
  }

  setData<DataType>(DataType data) {
    rawResponse.data = data;
    return this;
  }

  String getMsg() {
    return rawResponse.msg!;
  }

  String? getNetworkErrorMsg() {
    return rawResponse.networkMsg;
  }

  int getStatus() {
    return rawResponse.status!;
  }

  int getTotalPages() {
    return rawResponse.totalPages;
  }

  int getCurrentPage() {
    return rawResponse.currentPage;
  }
}
