// Simple pager (components/ui/Pagination.tsx): "Showing 21–40 of 95" with
// previous / next.

import 'dart:math' as math;

import 'package:flutter/material.dart';

class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.total,
    required this.pageSize,
    required this.onPage,
  });

  final int page;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final pages = math.max(1, (total / pageSize).ceil());
    final from = total == 0 ? 0 : (page - 1) * pageSize + 1;
    final to = math.min(page * pageSize, total);

    return Row(
      children: [
        Expanded(
          child: Text(
            'Showing $from–$to of $total',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
          ),
        ),
        IconButton(
          tooltip: 'Previous page',
          onPressed: page > 1 ? () => onPage(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '$page / $pages',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
        ),
        IconButton(
          tooltip: 'Next page',
          onPressed: page < pages ? () => onPage(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}