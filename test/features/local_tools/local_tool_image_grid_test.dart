// 九宫格切图的几何计算：这块最该脱离 Canvas 测。
//
// 真实踩过的坑是「除不尽」：900 宽切 3 刀是 300/300/300 没问题，
// 但 1000 宽切 3 份，按 1000 ~/ 3 = 333 切会得到 333/333/334，
// 而如果均摊余数（333/334/333）就会在中间产生 1px 缝，拼回去对不上原图。
// 这里的断言锁的就是「三块严格拼回原尺寸」。
import 'package:box/features/local_tools/domain/local_tool_image_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('split 基本切分', () {
    test('900x900 切 3x3：9 块，每块 300x300', () {
      final rects = GridCutGeometry.split(width: 900, height: 900);

      expect(rects.length, 9);
      expect(rects.every((r) => r.width == 300 && r.height == 300), isTrue);
    });

    test('顺序是从左到右、从上到下（九宫格阅读序）', () {
      final rects = GridCutGeometry.split(width: 900, height: 900);

      expect(rects[0], const Rect(left: 0, top: 0, width: 300, height: 300));
      expect(rects[1], const Rect(left: 300, top: 0, width: 300, height: 300));
      expect(rects[2], const Rect(left: 600, top: 0, width: 300, height: 300));
      expect(rects[3], const Rect(left: 0, top: 300, width: 300, height: 300));
      expect(rects[8], const Rect(left: 600, top: 900 - 300, width: 300, height: 300));
    });

    test('除不尽时余数并入最后一块，三块严格拼回原宽', () {
      const width = 1000;
      final rects = GridCutGeometry.split(width: width, height: 900, rows: 3, cols: 3);

      final firstRow = rects.take(3).toList();
      final sum = firstRow.fold<int>(0, (s, r) => s + r.width);

      expect(sum, width, reason: '拼回去必须恰好等于原宽，不能多也不能少');
      expect(firstRow[0].width, 333);
      expect(firstRow[1].width, 333);
      expect(firstRow[2].width, 334, reason: '余数全给最后一块，别在中间开缝');
    });

    test('相邻块首尾相接，没有缝也没有重叠', () {
      final rects = GridCutGeometry.split(width: 1001, height: 997, rows: 3, cols: 3);

      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 2; c++) {
          final left = rects[r * 3 + c];
          final right = rects[r * 3 + c + 1];
          expect(right.left, left.right, reason: '横向相邻块必须首尾相接');
        }
      }
      for (var c = 0; c < 3; c++) {
        for (var r = 0; r < 2; r++) {
          final top = rects[r * 3 + c];
          final bottom = rects[(r + 1) * 3 + c];
          expect(bottom.top, top.bottom, reason: '纵向相邻块必须首尾相接');
        }
      }
    });

    test('非方形网格：2x4 给出 8 块', () {
      final rects = GridCutGeometry.split(width: 1600, height: 900, rows: 2, cols: 4);
      expect(rects.length, 8);
      expect(rects.first.width, 400);
      expect(rects.first.height, 450);
    });

    test('1x1 等于原图', () {
      final rects = GridCutGeometry.split(width: 123, height: 456, rows: 1, cols: 1);
      expect(rects.single, const Rect(left: 0, top: 0, width: 123, height: 456));
    });
  });

  group('split 的输入校验', () {
    test('尺寸非正抛 ArgumentError', () {
      expect(() => GridCutGeometry.split(width: 0, height: 100),
          throwsA(isA<ArgumentError>()));
      expect(() => GridCutGeometry.split(width: 100, height: -1),
          throwsA(isA<ArgumentError>()));
    });

    test('行列非正抛 ArgumentError', () {
      expect(() => GridCutGeometry.split(width: 100, height: 100, rows: 0),
          throwsA(isA<ArgumentError>()));
      expect(() => GridCutGeometry.split(width: 100, height: 100, cols: -3),
          throwsA(isA<ArgumentError>()));
    });

    test('切块数比像素还多时抛，而不是产生 0 宽块', () {
      expect(() => GridCutGeometry.split(width: 3, height: 3, rows: 10, cols: 10),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('suggestGrid 形状建议', () {
    test('正方形给 3x3', () {
      expect(GridCutGeometry.suggestGrid(1000, 1000), (3, 3));
    });

    test('横图给 2x4', () {
      expect(GridCutGeometry.suggestGrid(1920, 1080), (2, 4));
    });

    test('竖图给 4x2', () {
      expect(GridCutGeometry.suggestGrid(1080, 1920), (4, 2));
    });

    test('尺寸非法时回落到 3x3（不抛）', () {
      expect(GridCutGeometry.suggestGrid(0, 0), (3, 3));
    });
  });

  group('canSplitInto', () {
    test('块足够大时为 true', () {
      expect(canSplitInto(width: 900, height: 900, rows: 3, cols: 3), isTrue);
    });

    test('块小于 20px 时为 false（能跑但没意义）', () {
      expect(canSplitInto(width: 50, height: 50, rows: 3, cols: 3), isFalse);
    });

    test('输入非法为 false', () {
      expect(canSplitInto(width: 0, height: 100, rows: 3, cols: 3), isFalse);
      expect(canSplitInto(width: 100, height: 100, rows: 0, cols: 3), isFalse);
    });
  });
}
