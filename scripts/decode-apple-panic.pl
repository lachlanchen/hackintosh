#!/usr/bin/env perl
use strict;
use warnings;

binmode STDIN;
binmode STDOUT;

local $/;
my $packed = <STDIN>;

for (my $offset = 0; $offset + 7 <= length($packed); $offset += 7) {
    my $word = unpack("Q<", substr($packed, $offset, 7) . "\0");
    for my $index (0 .. 7) {
        print chr(($word >> (7 * $index)) & 0x7f);
    }
}

