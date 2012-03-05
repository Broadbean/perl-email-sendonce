package Email::SendOnce::Email;

# tiny compatibility layer around MIME::Lite & Email::Abstract

use strict;
use warnings;

sub new {
    my $class = shift;
    my $msg   = shift;

    if ( !$msg->isa('MIME::Lite') ) {
        require Email::Abstract;
        require Email::Sender::Simple;

        $msg = Email::Abstract->new($msg);
    }

    my $self = bless {
        raw => $msg,
    }, $class;

    return $self;
}

sub raw {
    return $_[0]->{raw} if @_ == 1;
    return $_[0]->{raw} == $_[1];
}

sub get {
    my $self = shift;
    my $header = shift;

    my $raw = $self->raw();
    if ( $raw->can('header_get') ) {
        # Email::Simple
        return $raw->header_get( $header );
    }

    if ( $raw->can('get_header') ) {
        # Email::Abstract
        return $raw->get_header( $header );
    }

    # MIME::Lite version
    return $raw->get( $header );
}

sub send {
    my $self = shift;

    my $raw = $self->raw();

    if ( $raw->can('send') ) {
        # MIME::Lite version
        return $raw->send();
    }

    # Email::Abstract version
    require Email::Sender::Simple;
    return Email::Sender::Simple->send($raw);
}

1;

__END__

=head1 NAME

Email::SendOnce::Email - message abstraction layer used by Email::SendOnce

Supports MIME::Lite & more if you have Email::Abstract installed
