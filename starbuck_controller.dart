import 'package:get/get_state_manager/get_state_manager.dart';

class StarbuckController extends GetxController {
  List<Map<String, dynamic>> deliveryCount = [
    {
      'sn': '23544788567',
      'name': 'เดอะสตรีท',
      'milk': 10,
      'bakery': 20,
    },
    {
      'sn': '98657458084',
      'name': 'Reserve Chao Phraya Riverfront',
      'milk': 10,
      'bakery': 20,
    },
    {
      'sn': '87568673783',
      'name': 'centralwOrld',
      'milk': 10,
      'bakery': 20,
    },
    {
      'sn': '45657876766',
      'name': 'แคมป์ เดวิส',
      'milk': 10,
      'bakery': 20,
    },
    {
      'sn': '27655434667',
      'name': 'แพชชั่น ช้อปปิ้งเดสติเนชั่น',
      'milk': 10,
      'bakery': 20,
    },
    {
      'sn': '98765442222',
      'name': 'สยามฟิวเจอร์ นวมินทร์',
      'milk': 10,
      'bakery': 20
    },
    {
      'sn': '123456567662',
      'name': 'เดอะ คริสตัล พีทีที ชัยพฤกษ์',
      'milk': 10,
      'bakery': 20,
    },
    {
      'sn': '9867023587678',
      'name': 'Motorway ขาออก ร้านที่ 2',
      'milk': 10,
      'bakery': 20,
    },
  ];
  List<Map<String, dynamic>> jobStarbuck = [
    {
      'jobNo': 'JO2111020002',
      'worksheet': [
        {
          'noId': 'ADC202110250004',
          'dcName': 'งานของศูนย์กระจาย(หลัก)',
          'dt': '25/10/2021 17:33',
          'workNo': 'DEL-IELC-202110250004',
          'typeJobCode': 'General',
          'typeJobName': 'ขนส่งสินค้าทั่วไป',
          'customerName': 'งาน DEL-IELC-202110250004',
          'packCount': 5,
          'pickupPack': 1,
          'deliveryPack': 1,
        },
        {
          'noId': 'ADC202110250004',
          'dcName': 'งานของศูนย์กระจาย(หลัก)',
          'dt': '25/10/2021 17:33',
          'workNo': 'DEL-IELC-202110250004',
          'typeJobCode': 'General',
          'typeJobName': 'ขนส่งสินค้าทั่วไป',
          'customerName': 'งาน DEL-IELC-202110250004',
          'packCount': 5,
          'pickupPack': 1,
          'deliveryPack': 1,
        },
      ]
    },
  ];
  String barcode = "";
}
