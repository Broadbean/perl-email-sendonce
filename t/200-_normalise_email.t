#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Email::SendOnce;

my %tests = (
    q{andy@broadbean.net} => [
        q{andy@broadbean.net},
    ],
    q{<andy@broadbean.net>} => [
        q{andy@broadbean.net},
    ],
    q{"Andy Jones" <andy@broadbean.net>} => [
        q{andy@broadbean.net},
    ],
    q{andy@broadbean.net,andy@broadbean.com} => [
        'andy@broadbean.net',
        'andy@broadbean.com',
    ],
    q{"Andy Jones" <andy@broadbean.net>, "Andy Jones" <andy@broadbean.com>} => [
        q{andy@broadbean.net},
        q{andy@broadbean.com},
    ],
    q{"Jones, Andy" <andy@broadbean.net>, "Andy Jones" <andy@broadbean.com>} => [
        q{andy@broadbean.net},
        q{andy@broadbean.com},
    ],
);

plan tests => scalar(keys %tests);

while ( my ($in, $out)  = each %tests ) {
    my @got = Email::SendOnce->_normalise_email( $in );
    is_deeply( \@got, $out, $in );
}

done_testing();
