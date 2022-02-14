import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/types/ResponseStruct.dart';

class UnauthorizedAccess extends RequestException{
  UnauthorizedAccess(ResponseStruct response) : super(response);
}