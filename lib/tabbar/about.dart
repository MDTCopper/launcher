import 'package:flutter/cupertino.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutState();
}
class _AboutState extends State<AboutPage>{
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Duration(seconds: 1),
      child: Text('关于'),
    );
  }

}