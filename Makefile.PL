use inc::Module::Install;

name     'Email-SendOnce';
all_from 'lib/Email/SendOnce.pm';
author   q{Broadbean Technology <andy@broadbean.com>};
license  'perl';

build_requires 'Test::More';

auto_install;

WriteAll;

