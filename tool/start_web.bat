@echo off
cd /d C:\Users\Admin\box-inspect
flutter run -d web-server --web-port 8081 > C:\Users\Admin\box-inspect\web_server.log 2>&1
