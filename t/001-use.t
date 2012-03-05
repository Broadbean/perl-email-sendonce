#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use DBI;

# Setup our the mail classes that we support
my %classes = (
    'MIME::Lite'      => \&new_mime_lite,

    'Email::Abstract' => \&new_email_abstract,

    # and anything that Email::Abstract supports
    'Mail::Message'   => \&new_mail_message,
    'Email::Simple'   => \&new_email_simple,
    'Mail::Internet'  => \&new_mail_internet,
);

# Setup our tests
my $class = 'Email::SendOnce';

# initialise DB
my $dsn      = $ENV{DBI_DSN} || "dbi:SQLite:dbname=:memory:";
my $username = $ENV{DBI_USERNAME};
my $password = $ENV{DBI_PASSWORD};

my $dbh = eval { DBI->connect($dsn, $username, $password) };
if ( !$dbh ) {
    plan skip_all => "Unable to connect to database ($@), perhaps SQLite is not installed";
}

# Set the test plan
my $tests_per_mailer = 5;
plan tests => $tests_per_mailer * scalar(keys %classes) + 1;

#### Run tests
use_ok( $class );

# now we can initialise a database for testing
$class->initialise_database( $dbh );

while ( my ($mail_class, $mail_generator) = each %classes ) {
    my $has_mail_class = eval "use $mail_class; 1";

    # MIME::Lite sends it's own emails
    # The rest fallback to Email::Sender::Simple
    my $sender_class = $mail_class eq 'MIME::Lite' ? '' : 'Email::Sender::Simple';
    my $has_sender_class = $sender_class 
                         ? eval "use $sender_class; 1"
                         : 1; # we use mime::lite's build in mail sender

    SKIP: {
        skip "$mail_class is not installed", $tests_per_mailer unless $has_mail_class;
        skip "$sender_class is not installed", $tests_per_mailer unless $has_sender_class;

        {
            my $msg = $mail_generator->();

            my $sent = $class->run_once(
                $dbh,
                $msg,
            );

            ok( $sent, "sent the message the first time" );
        };

        {
            my $msg = $mail_generator->();

            my $sent = $class->run_once(
                $dbh,
                $msg,
            );

            ok( !$sent, "did not send the message the second time" );
        };

        {
            my $msg = $mail_generator->({
                To => q{drop@broadbean.net},
            });

            my $sent = $class->run_once(
                $dbh,
                $msg,
            );

            ok( $sent, "did send the message to a new recipient" );
        };

        {
            my $msg = $mail_generator->({
                Subject => q{Testing, Testing, one, two, three, four},
            });

            my $sent = $class->run_once(
                $dbh,
                $msg,
            );

            ok( $sent, "did send the message with a new subject line" );
        };

        sleep 2;

        {
            my $msg = $mail_generator->();

            my $sent = $class->run_once(
                $dbh,
                $msg, {
                    every => '1s',
                },
            );

            ok( $sent, "did send the message as it has been more than one second since the last mesg" );
        };
    };
}

sub new_mime_lite {
    my $options_ref = shift || {};

    my %options = mail_defaults($options_ref);
    my $msg = MIME::Lite->new(
        %options,
    );
    return $msg;
}

sub new_email_abstract {
    my $options_ref = shift || {};

    my $email = Email::Abstract->new(
        new_email_simple($options_ref),
    );

    return $email;
}


sub new_mail_message {
    my $options_ref = shift || {};

    my %options = mail_defaults($options_ref);

    $options{data} = delete $options{Data};

    my $msg = Mail::Message->build( %options );
    return $msg;
}

sub new_email_simple {
    my $options_ref = shift || {};

    my %options = mail_defaults($options_ref);

    my $email = Email::Simple->create();
    $email->body_set(delete $options{Data});

    while ( my ($header, $data) = each %options ) {
        $email->header_set( $header => $data );
    }

    return $email;
}

sub new_mail_internet {
    my $options_ref = shift || {};

    my %options = mail_defaults($options_ref);

    my $msg = Mail::Internet->new(
        Body => [
            map { $_ . "\n" } split "\n", delete $options{Data}
        ],
    );

    while ( my ($header, $data) = each %options ) {
        $msg->add( $header => $data );
    }

    return $msg;
}

sub mail_defaults {
    my $options_ref = shift || {};
    my %options = (
        To   => q{andy@broadbean.net},
        From => q{drop@broadbean.net},
        Subject => q{Testing, Testing, one, two, three},
        Data    => 'Test',
        %$options_ref,
    );

    return %options;
}
