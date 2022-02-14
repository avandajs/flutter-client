import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/types/ResponseStruct.dart';

class InternetNetworkError extends RequestException{
  InternetNetworkError(ResponseStruct response) : super(response);
}