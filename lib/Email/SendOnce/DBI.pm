package Email::SendOnce::DBI;

use strict;
use warnings;

my $SQL_DBMS_NAME = 17;

sub new {
    my $class = shift;
    my $dbh  = shift;

    my $self = bless {
        raw => $dbh,
    }, $class;

    my $db_type = $dbh->get_info($SQL_DBMS_NAME);
    if ( $db_type =~ m/sqlite/i ) {
        $self->{to_epoch} = \&sqlite_to_epoch;
        $self->{now}      = \&sqlite_now;
    }
    else {
        $self->{to_epoch} = \&mysql_to_epoch;
        $self->{now}      = \&mysql_now;
    }

    return $self;
}

# Routines to "pinch" from DBI
sub do       { return shift->{raw}->do(@_);      }
sub prepare  { return shift->{raw}->prepare(@_); }
sub errstr   { return shift->{raw}->errstr();    }

# cross database compatibility layer
# returns SQL for the appropriate DB engine
sub to_epoch { return shift->{to_epoch}->(@_); }
sub now      { return shift->{now}->(@_) }

# DB specific routines
sub sqlite_to_epoch { return 'strftime("%s", ' . $_[1] . ')'; }
sub mysql_to_epoch  { return 'UNIX_TIMESTAMP(' . $_[1]. ')';  }

sub sqlite_now      { return "datetime('now')"; }
sub mysql_now       { return "NOW()";           }

1;

__END__

=head1 NAME

Email::SendOnce::DBI - Datetime compatibility layer on DBI

Tested with SQLite & MySQL, but may work on others
