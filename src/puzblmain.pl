#!/usr/bin/perl -w

# PUZBL
# puzblmain.pl #---
# Developer: Branitskiy Alexander <schurshick@yahoo.com>
use puzbl; #---
use strict;
use warnings;

START: main(\@ARGV);

sub main
{
    my $args = (defined $_[0]) ? shift : undef;
    my $puzbl_obj = puzbl->new();
    $puzbl_obj->run($args);
}

