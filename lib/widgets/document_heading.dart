String documentHeading(String name, int pageCount) =>
    '$name - $pageCount page${pageCount == 1 ? '' : 's'}';
