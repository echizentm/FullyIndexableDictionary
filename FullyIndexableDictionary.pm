package FullyIndexableDictionary;
use strict;
use warnings;

use constant {
    SMALL_BLOCK_SIZE => 32,
    LARGE_BLOCK_SIZE => 256,
    BLOCK_RATE       => 8,
};

sub new {
    my ($class, $self) = @_;
    $self = {} unless ($self);
    return bless($self, $class);
}

sub total_size {
    my ($self) = @_;

    return $self->{size};
}

sub size {
    my ($self, $bit) = @_;

    if ($bit) { return $self->{size1}; }
    else      { return $self->{size} - $self->{size1}; }
}

sub to_string {
    my ($self, $separator) = @_;

    return join($separator, map {
        join('', reverse(split('', sprintf("%032b", $_))));
    } @{$self->{bit_vector}});
}

sub clear {
    my ($self) = @_;

    $self->{size}            = 0;
    $self->{size1}           = 0;
    $self->{bit_vector}      = ();
    $self->{rank_dictionary} = ();
}

sub get {
    my ($self, $index) = @_;

    return unless ($index >= 0);
    return unless ($self->{size} and $index < $self->{size});
    my $q = int($index / SMALL_BLOCK_SIZE);
    my $r =     $index % SMALL_BLOCK_SIZE;
    my $m = 0x1 << $r;
    $self->{bit_vector}[$q] = 0 unless ($self->{bit_vector}[$q]);
    return $self->{bit_vector}[$q] & $m;
}

sub set {
    my ($self, $index, $bit) = @_;

    return                     unless ($index >= 0);
    $self->{size} = $index + 1 unless ($self->{size} and $index < $self->{size});
    my $q = int($index / SMALL_BLOCK_SIZE);
    my $r =     $index % SMALL_BLOCK_SIZE;
    my $m = 0x1 << $r;
    if ($bit) { $self->{bit_vector}[$q] |=  $m; }
    else      { $self->{bit_vector}[$q] &= ~$m; }
}

sub build {
    my ($self) = @_;

    $self->{size1}           = 0;
    $self->{rank_dictionary} = ();
    my $index = 0;
    for my $block (@{$self->{bit_vector}}) {
        push(@{$self->{rank_dictionary}}, $self->{size1}) if ($index % BLOCK_RATE == 0);
        $self->{size1} += $self->_rank32($block, SMALL_BLOCK_SIZE, 1);
        $index++;
    }
}

sub rank {
    my ($self, $index, $bit) = @_;

    return unless ($index >= 0);
    return unless ($self->{size} and $index <= $self->{size});

    return 0 if ($index == 0);
    $index--;
    my $q_large = int($index / LARGE_BLOCK_SIZE);
    my $q_small = int($index / SMALL_BLOCK_SIZE);
    my $r       = $index % SMALL_BLOCK_SIZE;

    my $rank = $self->{rank_dictionary}[$q_large];
    $rank = $q_large * LARGE_BLOCK_SIZE - $rank unless ($bit);
    my $index_small = $q_large * BLOCK_RATE;
    while ($index_small < $q_small) {
        $rank += $self->_rank32($self->{bit_vector}[$index_small], SMALL_BLOCK_SIZE, $bit);
        $index_small++;
    }
    $rank += $self->_rank32($self->{bit_vector}[$q_small], $r + 1, $bit);
    return $rank;
}

sub select {
    my ($self, $index, $bit) = @_;

    return unless ($index < $self->size($bit));

    my $left  = 0;
    my $right = @{$self->{rank_dictionary}};
    while ($left < $right) {
      my $pivot = int(($left + $right) / 2);
      my $rank  = $self->{rank_dictionary}[$pivot];
      $rank = $pivot * LARGE_BLOCK_SIZE - $rank unless ($bit);
      if ($index < $rank) { $right = $pivot; }
      else                { $left  = $pivot + 1; }
    }
    $right--;

    if ($bit) { $index -= $self->{rank_dictionary}[$right]; }
    else      { $index -= $right * LARGE_BLOCK_SIZE - $self->{rank_dictionary}[$right]; }
    my $index_small = $right * BLOCK_RATE;
    while (1) {
      my $rank = $self->_rank32($self->{bit_vector}[$index_small], SMALL_BLOCK_SIZE, $bit);
      last if ($index < $rank);
      $index_small++;
      $index -= $rank;
    }
    return $index_small * SMALL_BLOCK_SIZE +
           $self->_select32($self->{bit_vector}[$index_small], $index, $bit);
}

sub write {
    my ($self, $filename) = @_;

    open(my $handler, '>', $filename) or die "cannot open $filename.\n";
    binmode $handler;
    print $handler pack('I', $self->{size});
    print $handler pack('I', $self->{size1});
    print $handler pack('I', scalar(@{$self->{bit_vector}}));
    print $handler pack('I', scalar(@{$self->{rank_dictionary}}));
    map { print $handler pack('I', $_ ? $_ : 0); } @{$self->{bit_vector}};
    map { print $handler pack('I', $_ ? $_ : 0); } @{$self->{rank_dictionary}};
    close($handler);
}

sub read {
    my ($self, $filename) = @_;

    open(my $handler, '<', $filename) or die "cannot open $filename.\n";
    binmode $handler;
    $self->clear();
    my $buf;
    read($handler, $buf, 4);
    $self->{size} = unpack('I', $buf);
    read($handler, $buf, 4);
    $self->{size1} = unpack('I', $buf);
    read($handler, $buf, 4);
    my $bit_vector_size = unpack('I', $buf);
    read($handler, $buf, 4);
    my $rank_dictionary_size = unpack('I', $buf);
    while ($bit_vector_size) {
        read($handler, $buf, 4);
        push(@{$self->{bit_vector}}, unpack('I', $buf));
        $bit_vector_size--;
    }
    while ($rank_dictionary_size) {
        read($handler, $buf, 4);
        push(@{$self->{rank_dictionary}}, unpack('I', $buf));
        $rank_dictionary_size--;
    }
    close($handler);
}

sub _rank32 {
    my ($self, $block, $index, $bit) = @_;

    $block = 0x00000000 unless ($block);
    $block = ~$block unless ($bit);
    $block <<= (SMALL_BLOCK_SIZE - $index);
    $block = (($block & 0xaaaaaaaa) >>  1)
           +  ($block & 0x55555555);
    $block = (($block & 0xcccccccc) >>  2)
           +  ($block & 0x33333333);
    $block = (($block & 0xf0f0f0f0) >>  4)
           +  ($block & 0x0f0f0f0f);
    $block = (($block & 0xff00ff00) >>  8)
           +  ($block & 0x00ff00ff);
    $block = (($block & 0xffff0000) >> 16)
           +  ($block & 0x0000ffff);
    return $block;
}

sub _select32 {
    my ($self, $block, $index, $bit) = @_;

    $block = 0x00000000 unless ($block);
    $block = ~$block unless ($bit);
    my $block1 = (($block  & 0xaaaaaaaa) >>  1)
               +  ($block  & 0x55555555);
    my $block2 = (($block1 & 0xcccccccc) >>  2)
               +  ($block1 & 0x33333333);
    my $block3 = (($block2 & 0xf0f0f0f0) >>  4)
               +  ($block2 & 0x0f0f0f0f);
    my $block4 = (($block3 & 0xff00ff00) >>  8)
               +  ($block3 & 0x00ff00ff);

    $index++;
    my $pos = 0;
    my $value4 = ($block4 >> $pos) & 0x0000ffff;
    if ($index > $value4) { $index -= $value4; $pos += 16; }
    my $value3 = ($block3 >> $pos) & 0x000000ff;
    if ($index > $value3) { $index -= $value3; $pos +=  8; }
    my $value2 = ($block2 >> $pos) & 0x0000000f;
    if ($index > $value2) { $index -= $value2; $pos +=  4; }
    my $value1 = ($block1 >> $pos) & 0x00000003;
    if ($index > $value1) { $index -= $value1; $pos +=  2; }
    my $value0 = ($block  >> $pos) & 0x00000001;
    if ($index > $value0) { $index -= $value0; $pos +=  1; }
    return $pos;
}

1;

