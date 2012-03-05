package Email::SendOnce;

use 5.006;
use strict;
use warnings;

use Digest::SHA1 qw(sha1_base64);

use Email::SendOnce::Email;
use Email::SendOnce::DBI;

my $TABLE = q{no_notifications_sent};

our $VERSION = '0.01'; # remember to update docs below too

# default is to send one notification per day
my $DEFAULT_EVERY_SECS = 24 * 60 * 60;

sub run_once {
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

Quick summary of what the module does.

Perhaps a little code snippet.

    use Email::SendOnce;

    my $foo = Email::SendOnce->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

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

