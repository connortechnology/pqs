use strict;
package openprint::Label;
our @ISA = qw(openprint::Object);
require openprint::Object;
require openprint::LabelType;

use openprint ();
use vars qw( $log $dbh $debug $table $serial %fields %find_fields %transforms %defaults );
*log = \$openprint::log;
*dbh = \$openprint::dbh;

require sql;

$debug = 0;
$table = 'labels';
$serial = 'labels_id_seq';
%fields = (
	id			=>	'id',
	type_id		=>	'type_id',
	reference	=>	'reference',
	content		=>	'content',
	docket		=>	'docket',
	created_on	=>	'created_on',
	deleted		=>	'deleted',
);
%find_fields = (
	company_id	=>	'(SELECT DISTINCT company_id FROM Projects WHERE Projects.lngDocketNumber=labels.docket)',
	type				=>	'(SELECT name FROM labeltypes where labeltypes.id=type_id)',
);

%transforms = (
	docket	=>	[ 's/\D//g' ],
);

%defaults = (
	docket		=>	undef,
	created_on	=>	q`'NOW()'`,
	deleted			=>	'0',
);

sub load {
	my ( $self, $data ) = @_;
	$self->SUPER::load( $data );
	%{$$self{data}} = sql::execute( undef, undef, 'SELECT name, value FROM label_data WHERE label_id=?', $$self{id} ) if $$self{id};
} # end sub load

sub save {
	my ( $self, $param ) = @_;

	my %data = %{$$self{data}} if $$self{data};
	my $ac = sql::start_transaction( $openprint::dbh );
	my $error = $self->SUPER::save( $param );
	if ( ! $error ) {
		sql::execute(undef,undef,'DELETE FROM Label_Data WHERE label_id=?', $$self{id} );
		foreach my $k ( keys %data ) {
			sql::insert( undef, undef, 'Label_data', 'label_id', $$self{id}, 'name', $k, 'value', $data{$k} );
		} # end foreach
	} # end if
	sql::end_transaction( $openprint::dbh, $ac );
	%{$$self{data}} = %data;
	return $error;
} # end sub save

sub destroy {
    my $ac = sql::start_transaction( );
    sql::execute( undef, undef, q{DELETE FROM Label_data WHERE label_id=?}, $_[0]{id} );
    sql::execute( undef, undef, q{DELETE FROM Labels WHERE id=?}, $_[0]{id} );
    sql::end_transaction( undef, $ac );
} # end sub destroy

sub Order {
	$_ = openprint::Order->find_one(docket=>$_[0]{docket}) if $_[0]{docket};
	$_ = new openprint::Order() if ! $_;
	return $_;
} # end sub Order

sub Project {
	$_ = openprint::Project->find_one(docket=>$_[0]{docket});
	$_ = new openprint::Project() if ! $_;
	return $_;
} # end sub Project

sub Type {
	return new openprint::LabelType( $_[0]{type_id} );
} # end sub Type

sub set_data {
	my $self = shift;
	my %new_data = @_;	
	my @changes;
	foreach my $k ( keys %new_data ) {
		if ( exists $$self{data}{$k} ) {
			if ( $$self{data}{$k} ne $new_data{$k} ) {	
				push @changes, "$k changed from $$self{data}{$k} to $new_data{$k}";
				$$self{data}{$k} = $new_data{$k};
				sql::update(undef,undef, 'Label_data', [ 'label_id=? AND name=?', $$self{id}, $k ], value=>$new_data{$k} );
			}
		} else {
			push @changes, "$k set to $new_data{$k}";
			$$self{data}{$k} = $new_data{$k};
			sql::insert(undef,undef, 'Label_data', label_id=>$$self{id}, name=>$k, value=>$new_data{$k} );
		}
	} # end foreach
	(new openprint::Log())->save({object_id=>$$self{id},object_type=>ref$self,action=>'Edit', note=>'Document Changed:<br/>'.join('<br/>', @changes) }) if @changes;
} # end sub set_data

sub get_data {
	my $self = shift;
	return @{$$self{data}}{@_};
} # end sub get_data

sub copy {
	my $self = shift;
	my $new = new openprint::Label();
	@$new{keys %fields} = @$self{keys %fields};
	delete $$new{id};
	foreach my $k ( keys %{$$self{data}} ) {
		$$new{data}{$k} = $$self{data}{$k};
	} # end foreach
	return $new;
} # end sub copy

sub url {
	return '/employee/production/labels/label.html?id='.$_[0]{id}.'&docket='.$_[0]{docket};
}
sub link_to {
	return sprintf('<a href="%s">%s</a>', $_[0]->url(), @_ > 1 ? $_[1] :  join(' ', $_[0]->Type()->name(), $_[0]{reference} ) );
} # end sub link_to

sub notify_csr {
	my ( $Label ) = @_;

	my $Project = $Label->Project();
	my $CSR;
	if ( $Project and $Project->Company()->salesrep_id() ) {
		$CSR = new openprint::User( $Project->Company()->salesrep_id() );
	} # end if
	if ( ! $CSR ) {
		return;
	}

	my $Notification = openprint::User_Notification->find_one( type=>$Label->Type()->name().' Creation', user_id=>$CSR->id() );
	if ( (!$Notification) or $Notification->value() ne 'Yes' ) {
		return;
	} # end if

	my $email_template = ssi::slurp_content( '/email_template.html' );
	my @attachments;
	my %info;
	$info{Label} = $Label;
	$info{base_href} = $openprint::config{InternalSiteURL};

	$info{ReplacementText} = '
<br/>
Click to view ' . $Project->production_link_to( 'Docket ' . $Project->docket() ) . '<br/>
<br/>
Click to view this ' . $Label->link_to() . ', however it may not be filled in yet.<br/>';

	my $Email = new openprint::Email();
	my $results .= $Email->send(
#BCC  =>  'iconnor@point-one.com',
			TO		=>	$CSR,
			FROM    =>  $openprint::User,
			SUBJECT =>  "New " . $Label->Type()->name() . ' created for docket ' . $Label->docket() . ( $$Label{reference} ? ' ref ' . $$Label{reference} : '' ),
			HTML_BODY	=>	ssi::variable_substitution( \$email_template, \%info ),
			);
	(new openprint::Log())->save({
			action=>'Notified CSR', 
			Object=>$Label,
			note=> 'Emailed from ' . $openprint::User->link_to() . ' to ' . $CSR->link_to(),
			});
	return $results;
} # end sub notify_csr

sub reference {
	my $self = shift;
	$$self{reference} = shift if @_;

	if ( !$$self{reference} ) {
		my $ref = $self->get_data('reference_default');
		if ( $ref ) {
$log->debug("Have $ref");
			$ref =~ s/%([^%]+)%/$self->get_data($1)/;

			$$self{reference} = $ref;
} else {
$log->debug("No Have reference in label");
		}
	}
	return $$self{reference};
}


1;
__END__
