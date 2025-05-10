import 'package:flutter/cupertino.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadState();
}
class _DownloadState extends State<DownloadPage>{
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Duration(seconds: 1),
      child: Text('下载'),
    );
  }
}