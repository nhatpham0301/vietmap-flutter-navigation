# Vietmap Flutter Navigation

Vietmap Flutter Navigation

Liên hệ [vietmap.vn](https://vietmap.vn) để đăng kí key hợp lệ.

## Getting started

Thêm thư viện vào file pubspec.yaml
```yaml
  vietmap_flutter_navigation: latest_version
```

Kiểm tra phiên bản của thư viện tại [https://pub.dev/packages/vietmap_flutter_navigation](https://pub.dev/packages/vietmap_flutter_navigation)
 
hoặc chạy lệnh sau để thêm thư viện vào project:
```bash
  flutter pub add vietmap_flutter_navigation
```
## Cấu hình cho Android


Thêm đoạn code sau vào build.gradle (project) tại path android/build.gradle

```gradle
 maven { url "https://jitpack.io" }
```


như sau


```gradle

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url "https://jitpack.io" }
    }
}
```


## Cấu hình cho iOS
Thêm đoạn code sau vào file Info.plist
```
	<key>VietMapAPIBaseURL</key>
	<string>https://maps.vietmap.vn/api/navigations/route/</string>
	<key>VietMapAccessToken</key>
	<string>YOUR_API_KEY_HERE</string>
	<key>VietMapURL</key>
	<string>https://run.mocky.io/v3/ff325d44-9fdd-480f-9f0f-a9155bf362fa</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>This app requires location permission to working normally</string>
	<key>NSLocationAlwaysUsageDescription</key>
	<string>This app requires location permission to working normally</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>This app requires location permission to working normally</string>
```


## Các tính năng chính


Khai báo các biến cần thiết và hàm cấu hình khởi tạo
```dart
  late MapOptions _navigationOption;
  final _vietmapNavigationPlugin = VietMapNavigationPlugin();

  List<WayPoint> wayPoints = [
    WayPoint(name: "origin point", latitude: 10.759091, longitude: 106.675817),
    WayPoint(
        name: "destination point", latitude: 10.762528, longitude: 106.653099)
  ];
  /// Hiển thị hình ảnh dẫn đường vào ngã rẽ tiếp theo
  Widget instructionImage = const SizedBox.shrink();

  Widget recenterButton = const SizedBox.shrink();
  RouteProgressEvent? routeProgressEvent;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    if (!mounted) return;
    _navigationOption = _vietmapNavigationPlugin.getDefaultOptions();
    _navigationOption.simulateRoute = false;

    _navigationOption.apiKey =
        'YOUR_API_KEY_HERE';
    _navigationOption.mapStyle =
        "https://run.mocky.io/v3/ff325d44-9fdd-480f-9f0f-a9155bf362fa";

    _vietmapNavigationPlugin.setDefaultOptions(_navigationOption);
  }
```

Hiển thị Navigation view, bao gồm bản đồ và đường đi, điều hướng dẫn đường
```dart
          NavigationView(
            mapOptions: _navigationOption,
            onMapCreated: (controller) {
              _controller = controller;
            },
            onRouteProgressChange: (RouteProgressEvent routeProgressEvent) {
              setState(() {
                this.routeProgressEvent = routeProgressEvent;
              });
              _setInstructionImage(routeProgressEvent.currentModifier,
                  routeProgressEvent.currentModifierType);
            },
          ),
```


Thêm banner widget chỉ dẫn điều hướng 
```dart
            BannerInstructionView(
              routeProgressEvent: routeProgressEvent,
              instructionIcon: instructionImage,
            )
```
Hàm set hình ảnh dẫn đường
```dart
  _setInstructionImage(String? modifier, String? type) {
    if (modifier != null && type != null) {
      List<String> data = [
        type.replaceAll(' ', '_'),
        modifier.replaceAll(' ', '_')
      ];
      String path = 'assets/navigation_symbol/${data.join('_')}.svg';
      setState(() {
        instructionImage = SvgPicture.asset(path, color: Colors.white);
      });
    }
  }
```
Danh sách các hình ảnh dẫn đường được lưu trong thư mục [này](./example/assets/navigation_symbol), sao chép và dán vào project của bạn để sử dụng.

File thiết kế có thể tham khảo [tại đây](https://www.figma.com/file/rWyQ5TNtt6E5l8tPEE9Tkl/VietMap-navigation-symbol?type=design&node-id=1%3A457&mode=design&t=yszRZCTouxAdYXXJ-1)



Thêm các nút như xem tổng quan đường đi, về giữa để điều hướng dẫn đường
```dart
            BottomActionView(
              recenterButton: recenterButton,
              controller: _controller,
              onOverviewCallback: _showRecenterButton,
              onStopNavigationCallback: _onStopNavigation,
              routeProgressEvent: routeProgressEvent
            )
```
Các hàm thường sử dụng
```dart
          /// Tìm đường mới từ 2 điểm, waypoint1 là điểm bắt đầu, 
          /// waypoint2 là điểm kết thúc.
            _controller?.buildRoute(wayPoints: <Waypoint>[waypoint1,waypoint2]);

          /// Bắt đầu dẫn đường, gọi sau khi đã gọi hàm buildRoute phía trên
            _controller?.startNavigation();

          /// Hàm tìm đường và bắt đầu dẫn đường khi tìm được đường đi
            _controller?.buildAndStartNavigation(
                wayPoints: wayPoints: <Waypoint>[waypoint1,waypoint2],
                profile: DrivingProfile.drivingTraffic);
          
          /// Hàm về giữa sau khi nhấn xem tông quan đường đi 
          /// hoặc người dùng di chuyển bản đồ tới vị trí khác
          _controller?.recenter();

          /// Hàm xem tổng quát đường đi
          _controller?.overview();

          /// Hàm tắt tiếng khi dẫn đường
          _controller?.mute();

          /// Hàm kết thúc dẫn đường
          _controller?.finishNavigation();
```
Code mẫu màn hình dẫn đường [tại đây](./example/lib/main.dart)
# Lưu ý: Thay apikey được cung cấp vào toàn bộ tag _YOUR_API_KEY_HERE_ để ứng dụng hoạt động bình thường
![Navigation screen](/images/navigation.jpg)
