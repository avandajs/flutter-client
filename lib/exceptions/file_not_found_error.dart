import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/types/ResponseStruct.dart';

class FileNotFoundError extends RequestException{
  FileNotFoundError(ResponseStruct response) : super(response);
}