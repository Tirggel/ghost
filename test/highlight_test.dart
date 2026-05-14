import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

class SearchMatchSyntax extends md.InlineSyntax {
  SearchMatchSyntax(super.pattern) : super(caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text('search_match', match[0]!);
    parser.addNode(element);
    return true;
  }
}

class SearchMatchBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return RichText(
      text: TextSpan(
        text: element.textContent,
        style: const TextStyle(backgroundColor: Colors.yellow, color: Colors.black),
      ),
    );
  }
}

void main() {
  testWidgets('Test Markdown Syntax Highlighting', (WidgetTester tester) async {
    const text = 'This is a test of the search function with a test word.';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MarkdownBody(
          data: text,
          inlineSyntaxes: [SearchMatchSyntax('test')],
          builders: {'search_match': SearchMatchBuilder()},
        ),
      ),
    ));

    expect(find.byType(RichText), findsWidgets);
  });
}
