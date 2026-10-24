# LockSleeve 0.2

평소에는 원래 배경을 표시하고, 잠금화면에는 Apple Music의 현재 곡을 앨범 배경으로 표시하는 macOS 메뉴바 앱입니다. 기본은 Dock에 표시됩니다. 앱의 **백그라운드 실행** 버튼을 누르면 창과 Dock 아이콘을 숨기고 동기화는 계속합니다. 메뉴바 음표 → **Dock에 표시**로 일반 모드로 돌아올 수 있습니다. 선택은 다음 실행에도 유지됩니다. 빌드 후 `build/LockSleeve.app`에서 실행합니다.

## 사용

1. 앱을 실행하고 **앨범 배경 동기화 시작**을 누릅니다.
2. Music 자동화 권한을 허용하고 노래를 재생합니다.
3. 메뉴바 음표에서 창 열기·미리보기·배경 복원·종료를 제어합니다.

흐릿한 앨범 배경, 큰 표지, 곡 제목과 가수를 표시합니다. 검은색 덮개는 20%입니다. 곡 정보와 재생 위치를 1초마다 확인합니다. 가사가 있으면 왼쪽에 앨범, 오른쪽에 흰색 가사를 표시하고 현재 줄을 밝게 강조합니다. 가사는 배경과 분리된 텍스트 레이어로 표시하며 현재 구절이 바뀔 때 약 0.55초 동안 위로 이동하고 밝기를 전환합니다. 약 4구절(이전·현재·다음 2구절)을 표시하며 곡 시작과 끝에서도 표시 영역을 채웁니다. 글자 크기와 구절 간 여백을 조정해 시계·로그인 영역을 비웁니다. macOS의 동작 줄이기 설정을 존중합니다. 가사 변경만으로 배경 이미지를 다시 쓰지 않습니다.

Music 트랙에 저장된 가사를 읽거나 메뉴바의 **현재 곡 가사 파일 선택…**에서 UTF-8 LRC/TXT 파일을 불러올 수 있습니다. 선택한 파일은 현재 곡에 연결해 다음 재생에도 사용합니다. 시간 정보가 있는 LRC는 재생 위치와 동기화하고, 일반 가사는 첫 부분을 정적으로 표시합니다. 가사가 없는 곡은 기존 앨범 화면을 유지합니다. 저장된 동기화 가사나 직접 선택한 파일이 없으면 [LRCLIB](https://lrclib.net/docs)에 곡 제목·가수·앨범·길이를 보내 가사를 자동 조회합니다 (사용자 허용). 조회는 비동기로 수행하며 성공한 결과는 1시간, 실패한 결과는 1분 동안 메모리에 캐시합니다. 정확 조회에서 찾지 못하면 앨범명 없이 추가 검색하되 제목·가수와 재생 길이(±3초)가 일치하는 결과만 사용합니다. 가사 없음·HTTP 503 서버 혼잡·인터넷 연결 없음·응답 지연·조회 중 상태를 앱과 메뉴바에 표시하고 일시 오류는 2초 뒤 한 번 재시도하고, 정확 조회가 서버 오류여도 검색으로 확인합니다. 최종 실패한 조회는 약 65초 후 재시도합니다. 조회 실패 시 Music에 저장된 가사를 사용하고, 그것도 없으면 기존 앨범 화면을 유지합니다. 직접 선택한 파일 → Music 동기화 가사 → LRCLIB 동기화 가사 → Music 일반 가사 → LRCLIB 일반 가사 순서로 사용합니다. LRCLIB에도 가사가 없는 곡은 LRC 파일을 직접 불러올 수 있습니다.

## 확장 렌더러

`LockAlbumWallpaper.appex`를 시스템 배경 제공자로 한 번 선택하고 실행 중인 CAContext의 이미지 내용을 교체합니다. 곡 변경 때 WallpaperAgent를 재시작하거나 배경 저장소를 다시 쓰지 않습니다. 이미지 교체 시 이전 이미지가 준비된 새 이미지로 바뀌며, 읽기 실패 시에는 이전 이미지를 유지합니다.

확장은 샌드박스에서 실행되며 네트워크·임의 사용자 폴더 접근 권한이 없습니다. 메인 앱은 확장 소유 컨테이너의 `Library/Application Support/LockAlbum/Frames/current.png`를 원자적으로 갱신합니다. 확장은 0.2초 간격으로 이미지와 가사 상태 변경을 확인합니다. XPC 호스트는 /System 아래 Apple 서명 앱으로 제한합니다.

최초 활성화와 재생 정지·앱 종료 시 원래 배경 복원은 제공자 설정 전환이므로 WallpaperAgent를 재시작합니다. 이 순간의 깜박임은 남을 수 있습니다. 동기화 시작 시 원래 정적 배경 이미지를 확장 컨테이너의 desktop.png에 준비합니다. 평소에는 desktop.png, 잠긴 동안에는 current.png를 표시합니다. 메인 앱이 잠금·잠금 해제 알림과 세션 상태를 확인해 mode.json을 전달하고, 확장이 같은 CAContext 안에서 이미지만 교체합니다. 잠금·해제 때 배경 저장소를 수정하거나 WallpaperAgent를 재시작하지 않습니다. 전환 반영에는 약 0.2초가 걸릴 수 있습니다. 현재는 정적인 이미지 배경을 대상으로 하며 동영상·자동 순환 배경은 지원하지 않습니다.

원본 설정은 `~/Library/Application Support/LockAlbum/wallpaper-store-backup.plist`로 백업합니다. 앱의 배경 제공자 또는 앱이 만든 이미지를 가리키는 항목만 복원해 사용자가 따로 바꾼 배경을 덮어쓰지 않습니다. 강제 종료 후 다음 실행에서도 복원을 시도합니다.

## 검증

macOS 27.0.1 / Xcode 27에서 앱·확장 빌드 및 로컬 서명, PluginKit 등록, 시스템 호스트 연결, 이미지 읽기, CAContext 생성과 활성 surface를 확인했습니다. 실제 프레임 재읽기 시험에서 확장 PID와 WallpaperAgent PID가 유지되고 배경 저장소도 바뀌지 않는 것을 확인했습니다. 상시 앨범 버전의 바탕화면과 Control + Command + Q 잠금화면 표시는 사용자 시각 확인을 완료했습니다. 분리 버전에서 평소 원래 배경 → 잠금화면 앨범 → 잠금 해제 후 원래 배경 전환을 사용자 시각 확인했습니다. 전환 전후 확장과 WallpaperAgent 프로세스가 유지된 것도 확인했습니다. 동기화 중지 후 원래 바탕화면·화면 보호기 설정 복원도 확인했습니다.

비공개 WallpaperExtensionKit·CAContext 인터페이스를 쓰는 실험 버전입니다. macOS 업데이트 이후 동작이 달라질 수 있습니다. 정식 배포용 Developer ID 서명/공증은 없습니다.

## 개발

macOS 26 이상과 전체 Xcode가 필요합니다. macOS 27.0.1에서 검증했습니다.

```sh
git clone https://github.com/donghyun-0503/lockSleeve.git
cd lockSleeve
./scripts/build.sh
```

메인 앱은 swiftc, 확장은 `LockAlbumExtension.xcodeproj`의 ExtensionKit 타깃으로 빌드합니다. 전체 Xcode가 필요합니다. 첫 실행 전 확장을 등록한 뒤 앱을 여세요. 확장 변경 후에는 앱을 정상 종료한 뒤 다시 빌드하고 확장 등록을 갱신하세요.

```sh
pluginkit -a "$PWD/build/LockSleeve.app/Contents/Extensions/LockAlbumWallpaper.appex"
open build/LockSleeve.app
```

실행 중 무재시작 이미지 갱신 검증:

```sh
python3 scripts/verify-live-update.py
```

가사 시간·다중 타임스탬프·공백 구간·되감기 테스트:

```sh
xcrun swiftc Sources/Lyrics.swift Tests/LyricsTests.swift -o /tmp/lockalbum-lyrics-tests
/tmp/lockalbum-lyrics-tests
```

자동 조회 요청·캐시·취소·실패 처리 테스트 (실제 네트워크 사용 없음):

```sh
xcrun swiftc Sources/Lyrics.swift Tests/LyricsServiceTests.swift -o /tmp/lockalbum-lookup-tests
/tmp/lockalbum-lookup-tests
```

가사 화면 샘플 (앱 실행 및 배경 변경 없이 이미지 생성):

```sh
build/LockSleeve.app/Contents/MacOS/LockSleeve --render-test --lyrics /tmp/lockalbum-lyrics-preview.png
```

설정 변환·복원 테스트:

```sh
xcrun swiftc Sources/WallpaperStore.swift Tests/WallpaperStoreTests.swift -o /tmp/lockalbum-store-tests
/tmp/lockalbum-store-tests
```

확장 XPC 프로토콜, Codable 브리지, 런타임 래퍼는 MIT 라이선스 [Phosphene](https://github.com/kageroumado/phosphene) 코드를 참고·수정했습니다. 저작권 및 라이선스는 `ThirdParty/Phosphene-LICENSE`와 앱 번들에 포함됩니다.

앱 이름은 LockSleeve로 변경했습니다. 기존 설정과 Music 자동화 권한을 유지하기 위해 내부 번들 ID와 데이터 폴더의 LockAlbum 이름은 유지합니다.

가사 레이아웃·구절 간격·스크롤 방향 테스트:

```sh
xcrun swiftc Sources/LyricsLayout.swift Tests/LyricsLayoutTests.swift -o /tmp/lockalbum-layout-tests
/tmp/lockalbum-layout-tests
```

앱 창의 둥근 말풍선 버튼 또는 메뉴바 음표 → **가사 숨기기/가사 표시하기**로 표시를 전환합니다. 숨김 상태는 다음 실행에도 유지됩니다. 가사를 숨기면 앨범만 표시하며, 다시 켜면 현재 재생 위치의 가사로 돌아옵니다. 잠금화면 배경은 클릭을 받지 않으므로 전환은 앱이나 메뉴바에서 합니다.
