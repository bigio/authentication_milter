package Mail::Milter::Authentication::SenderID;

$VERSION = 0.1;

use strict;
use warnings;

use Mail::Milter::Authentication::Config qw{ get_config };
use Mail::Milter::Authentication::Util;

use Sys::Syslog qw{:standard :macros};

use Mail::SPF;

my $CONFIG = get_config();

sub eoh_callback {
    my ($ctx) = @_;
    dbgout( $ctx, 'CALLBACK', 'EOH', LOG_DEBUG );
    my $priv = $ctx->getpriv();
    return if ( !$CONFIG->{'check_senderid'} );
    return if ( $priv->{'is_local_ip_address'} );
    return if ( $priv->{'is_trusted_ip_address'} );
    return if ( $priv->{'is_authenticated'} );

    my $spf_server;
    eval {
        $spf_server =
          Mail::SPF::Server->new( 'hostname' => get_my_hostname($ctx) );
    };
    if ( my $error = $@ ) {
        log_error( $ctx, 'SenderID Setup Error ' . $error );
        add_auth_header( $ctx, 'senderid=temperror' );
        return;
    }

    my $scope = 'pra';

    my $identity = get_address_from( $priv->{'from_header'} );

    eval {
        my $spf_request = Mail::SPF::Request->new(
            'versions'      => [2],
            'scope'         => $scope,
            'identity'      => $identity,
            'ip_address'    => $priv->{'ip_address'},
            'helo_identity' => $priv->{'helo_name'},
        );

        my $spf_result = $spf_server->process($spf_request);
        #$ctx->progress();

        my $result_code = $spf_result->code();
        dbgout( $ctx, 'SenderIdCode', $result_code, LOG_INFO );

        if ( ! ( $CONFIG->{'check_senderid'} == 2 && $result_code eq 'none' ) ) {
            my $auth_header = format_header_entry( 'senderid', $result_code );
            add_auth_header( $ctx, $auth_header );
#my $result_local  = $spf_result->local_explanation;
#my $result_auth   = $spf_result->can( 'authority_explanation' ) ? $spf_result->authority_explanation() : '';
            my $result_header = $spf_result->received_spf_header();
            my ( $header, $value ) = $result_header =~ /(.*): (.*)/;
            prepend_header( $ctx, $header, $value );
            dbgout( $ctx, 'SPFHeader', $result_header, LOG_DEBUG );
        }
    };
    if ( my $error = $@ ) {
        log_error( $ctx, 'SENDERID Error ' . $error );
        add_auth_header( $ctx, 'senderid=temperror' );
        return;
    }
}

1;