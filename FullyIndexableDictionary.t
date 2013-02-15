#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 7;

BEGIN { use_ok('FullyIndexableDictionary') };

my @values = (0, 32, 33, 255, 256);
my @ranks  = (0, 1, 2, 3, 4);

my $fid = FullyIndexableDictionary->new();
map { $fid->set($_, 1); } @values;
$fid->build();

is($fid->total_size(), 257, 'total_size()');
is($fid->size(1)     , 5  , 'size(1)');
is($fid->size(0)     , 252, 'size(0)');

my @result_values;
my $value = 0;
while ($value < $fid->total_size()) {
    push(@result_values, $value) if ($fid->get($value));
    $value++;
}
is_deeply(\@result_values, \@values, 'get()');

my @result_ranks = map { $fid->rank($_, 1); } @values;
is_deeply(\@result_ranks, \@ranks, 'rank()');

my @result_selects = map { $fid->select($_, 1); } @ranks;
is_deeply(\@result_selects, \@values, 'select()');

