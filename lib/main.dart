import 'package:copperlauncher_main/tabbar/about.dart';
import 'package:copperlauncher_main/tabbar/download.dart';
import 'package:copperlauncher_main/tabbar/home.dart';
import 'package:copperlauncher_main/tabbar/setting.dart';
import 'package:flutter/material.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget{
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home:MainPage()
    );
  }
}



class MainPage extends StatefulWidget{
  const MainPage ({super.key});

  @override
  State<StatefulWidget> createState() =>  _MainPage();
}

class _MainPage extends State<MainPage>{
  int _currentIndex = 0 ;

  final List<Widget> _tabPages = [
    HomePage(),
    DownloadPage(),
    SettingPage(),
    AboutPage()
  ];

  final List<String> _pageName = ['游戏', '下载', '设置','关于'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 180,
        leading: Row(
          children: [
            Container(
              margin: EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: Image.asset('assets/images/copper.png'),
            ),
            Text('Copper',style: TextStyle(fontSize: 30,color: Colors.white,fontWeight: FontWeight.bold),)
          ],
        ),
        title: Text(_pageName[_currentIndex],style: TextStyle(color: Colors.white),),
        centerTitle: true,
        actions: [
          IconButton(
            iconSize: 40,
            color: Colors.orangeAccent,
            style: ButtonStyle(),
            icon: Icon(Icons.play_arrow_outlined),
            tooltip: '游戏',
            onPressed: (){
              setState(() {
                _currentIndex = 0;
              });
            },
          ),
          IconButton(
            iconSize: 36,
            color: Colors.orangeAccent,
            icon: Icon(Icons.download),
            onPressed: (){
              setState(() {
                _currentIndex = 1;
              });
            },
          ),
          IconButton(
            iconSize: 36,
            color: Colors.orangeAccent,
            icon: Icon(Icons.settings,),
            onPressed: (){
              setState(() {
                _currentIndex = 2;
              });
            },
          ),
          IconButton(
            iconSize:36,
            color: Colors.orangeAccent,
            icon: Icon(Icons.info_outline,),
            onPressed: (){
              setState(() {
                _currentIndex = 3;
              });
            },
          ),
        ],
        backgroundColor: Colors.black87,
      ),
      body: Container(
        alignment: Alignment.topCenter,
        color: Colors.black54,
        child: Container(
          margin: EdgeInsets.all(5),
          decoration:BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: _tabPages[_currentIndex],
        ),
      ),
    );
  }
}
