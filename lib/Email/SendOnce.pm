package Email::SendOnce;

use 5.006;
use strict;
use warnings;

use Digest::SHA1 qw(sha1_base64);

use Email::SendOnce::Email;
use Email::SendOnce::DBI;

my $TABLE = q{no_notifications_sent};

our $VERSION = '0.02'; # remember to update docs below too

# default is to send one notification per day
my $DEFAULT_EVERY_SECS = 24 * 60 * 60;

sub send {
    my $class = shift;
    my $dbh = Email::SendOnce::DBI->new(shift);
    my $msg = Email::SendOnce::Email->new(shift);
    my $options_ref = shift || {};

    # process options

    # only send the callback every $DEFAULT_EVERY_SECS
    # unless they specify their own
    my $every_secs = defined($options_ref->{every})
                   ? $class->_to_secs($options_ref->{every})
                   : $DEFAULT_EVERY_SECS;


    # build an identifier for this message
    my $id;
    if ( defined($options_ref->{id}) ) {
        # you can specify the id in the options
        $id = $options_ref->{id};
    }
    elsif ( defined($options_ref->{id_callback}) ) {
        # or supply an anonymous subref that returns the id
        $id = $options_ref->{id_callback}->( $dbh, $msg, $options_ref );
    }
    else {
        # or we will generate one based on the recipients+subject
        $id = $class->_get_id( $msg );
    }

    # see when we last sent this notification
    my $last_notified = $class->last_notification(
        $dbh, $id,
    );
    if ( $every_secs && defined($last_notified) ) {
        if ( $last_notified < $every_secs ) {
            return 0;
        }
    }

    # send the notification and remember that we have sent it
    if ( $options_ref->{send_callback} ) {
        $options_ref->{send_callback}->( $dbh, $msg, $options_ref );
    }
    else {
        $msg->send();
    }

    return $class->record_notification( $dbh, $id );
}

sub last_notification {
    my $class = shift;
    my $dbh   = shift;
    my $id    = shift;

    return $class->_last_notification( $dbh, $id );
}

sub record_notification {
    my $class = shift;
    my $dbh   = shift;
    my $id    = shift;

    return $class->_insert_notification($dbh,$id);
}

# returns a unique id for this email
# currently based on the recipients + the subject
sub _get_id {
    my $class = shift;
    my $msg   = shift;

    my @all_recipients = (
        $msg->get('To'),
        $msg->get('Cc'),
        $msg->get('Bcc'),
    );

    my @recipients = sort
                     map { $class->_normalise_email($_) }
                     grep { $_ }
                     @all_recipients;

    my $subject = $class->_normalise_subject( $msg->get('Subject') );

    return sha1_base64(join("\n", @recipients, $subject));
}

# Private methods
sub _normalise_email {
    my $class = shift;
    my $csv_addresses = shift;

    # remove names from the addresses
    # they may contain commas a mess up the next split
    $csv_addresses =~ s/\s*".+?"\s*//g;

    my @addresses = map {
        s/^<//; s/>$//; $_;
    }split /\s*,\s*/, $csv_addresses;

    return @addresses;
}

sub _normalise_subject {
    my $class = shift;
    my $subject = shift;
    $subject =~ s/^\s+//;
    $subject =~ s/^\s+$//;
    $subject =~ s/ +/ /g;

    return lc($subject);
}

sub _to_secs {
    my $class = shift;
    my $time  = shift or return 0;

    if ( $time =~ s/\s*d(?:ays?)?$//i ) {
        return $time * 24 * 60 * 60;
    }

    if ( $time =~ s/\s*h(?:rs?|ours?)?$//i ) {
        return $time * 60 * 60;
    }

    if ( $time =~ s/\s*m(?:ins?|inutes?)?$//i ) {
        return $time * 60;
    }

    $time =~ s/\s*s(?:ecs?|econds?)?$//i;

    return $time;
}

# DB queries

# inserts a row, if the row fails because the primary key
# exists, fallback to an update
sub _insert_notification {
    my $class = shift;
    my $dbh   = shift;
    my $id    = shift;

    my $sth = $dbh->prepare(
        'INSERT INTO '.$TABLE.'
                      (id, closed_at, created_at, updated_at)
               VALUES (?, NULL,     '.$dbh->now().','.$dbh->now().')',
    ) or die $dbh->errstr();

    my $insert_ok = eval {
        $sth->execute(
            $id,
        ) or die $sth->errstr();
    };

    if ( my $error = $@ ) {
        if ( $error =~ m/Duplicate entry|column id is not unique/ ) {
            return $class->_update_notification( $dbh, $id );
        }

        die $error;
    }

    return $insert_ok;
}

# updates the notification row in the db
sub _update_notification {
    my $class = shift;
    my $dbh   = shift;
    my $id    = shift;

    my $sth = $dbh->prepare(
        'UPDATE ' . $TABLE .'
            SET updated_at = ' . $dbh->now() . ',
                closed_at  = NULL
          WHERE id = ?',
    ) or die $dbh->errstr();

    $sth->execute(
        $id,
    ) or die $sth->errstr();

    return $sth->rows();
}

sub _last_notification {
    my $class = shift;
    my $dbh   = shift;
    my $id    = shift;

    my $sth = $dbh->prepare(
        'SELECT ' . $dbh->to_epoch($dbh->now()) .' - ' . $dbh->to_epoch('MAX(updated_at)')
       . ' FROM '.$TABLE.'
          WHERE id = ? AND closed_at IS NULL',
    ) or die $dbh->errstr();

    $sth->execute(
        $id,
    ) or die $sth->errstr();

    my ($last_notified_ago) = $sth->fetchrow_array();
    return $last_notified_ago;
}


# creates the tables that provide persistent storage
sub initialise_database {
    my $class = shift;
    my $dbh = shift;

    my $sql = <<__EOF_SQL;
CREATE TABLE IF NOT EXISTS $TABLE (
    id char(27) NOT NULL PRIMARY KEY,
    created_at datetime NOT NULL,
    updated_at datetime NOT NULL,
    closed_at  datetime DEFAULT NULL
)
__EOF_SQL

    my $sth = $dbh->prepare(
        $sql,
    ) or die $dbh->errstr();

    $sth->execute()
        or die $sth->errstr();

    return 1;
}

1; # End of Email::SendOnce

__END__

=head1 NAME

Email::SendOnce - limit how often an email is sent

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

It is useful to setup email alerts when the unexpected happens like
a third party service being unavailable.

If you are a high traffic site, you can end up with a lot of emails
and that volume can cause problems of it's own. Or perhaps it is just the hassle of deleting all the alerts.

This module surpresses duplicate emails from being sent so you only receive
one email per configurable time interval.

    use Email::SendOnce;

    my $dbh = DBI->connect($dsn, $username, $password);

    # create a database & tables to store our data in
    # only need to do this once
    Email::SendOnce->initialise_database($dbh);

    # build an email
    # also supports everything that Email::Abstract supports too
    my $msg = MIME::Lite->new();

    # send the email once per 24 hours
    Email::SendOnce->send($dbh, $msg);
    ...

The send history is stored in a database of your choice. SQLite and MySQL
have both been tested but others may work.

=head1 METHODS

=head2 send( $dbh, $msg, { OPTIONS_REF } )

=over 4

=item $dbh

  A DBI connection to a database. You can create the tables required
  in the database with C<initialise_database>

=item $msg

  A L<MIME::Lite> object or any object supported by L<Email::Abstract>
  if installed

=item $options_ref [OPTIONAL]

  Optional hash ref containing any of:

=over 4

=item every

how long until we send a duplicate email. In seconds or supports d, h, m, s units

=item id

if you want to supply your own id instead of letting us calculate it based on
the email

=item id_callback

subroutine ref that should return the id. Passed $dbh, $msg, $options_ref

=item send_callback

subroutine ref that can send the message. If unavailable, we send the email
using L<MIME::Lite> or L<Email::Sender::Simple>.

=back

=back

An email is considered a duplicate if it has the same subject and recipients.

You can also supply an id of your own to be used to deduplicate:

    Email::SendOnce->send($dbh, $msg, { id => $your_id });

or supply a subroutine ref that returns an id:

    Email::SendOnce->send($dbh, $msg, {
        id_callback => sub { my ($dbh, $msg, $options_ref) = @_; return $id++; },
    });

NB. The default id length in the table is 27 characters. If you want to use
longer you will need to alter the table definition

=head1 EXAMPLES

=head2 Notify me once every 10 minutes

    Email::SendOnce->send($dbh, $msg, { every => '10m' });

=head2 Send email using a different method

    Email::SendOnce->send($dbh, $msg, {
        send_callback => sub {
            my ($dbh, $msg, $options_ref) = @_;

            .. your custom sending code ..
        },
    });

=head2 initialise_database( $dbh )

Creates the tables required to storage the send history

=head2 last_notification( $dbh, $id )

Returns how long ago the last notification was sent with id = C<$id>. Unlikely
to be called directly

=head2 record_notification( $dbh, $id )

Records that we have sent a notification with id C<$id>. Unlikely to be called
directly

=head1 AUTHOR

Broadbean Technology, C<< <andy at broadbean.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-email-sendonce at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Email-SendOnce>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Email::SendOnce


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Email-SendOnce>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Email-SendOnce>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Email-SendOnce>

=item * Search CPAN

L<http://search.cpan.org/dist/Email-SendOnce/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Broadbean Technology.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

