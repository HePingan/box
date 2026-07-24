import 'package:flutter_test/flutter_test.dart';

import 'package:box/video/models/history_item.dart';

HistoryItem historyFor(String episodeUrl) => HistoryItem(
  vodId: 'vod-1',
  vodName: '示例',
  vodPic: '',
  sourceId: 'source-a',
  sourceName: '源',
  episodeName: '第 1 集',
  episodeUrl: episodeUrl,
  position: 1000,
  duration: 10000,
  updateTime: 1,
);

void main() {
  test('history storage key isolates episodes of the same video', () {
    expect(
      historyFor('https://cdn.example.com/e1.m3u8').storageKey,
      isNot(historyFor('https://cdn.example.com/e2.m3u8').storageKey),
    );
  });
}
