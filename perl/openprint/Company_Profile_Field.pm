use strict;
package openprint::Company_Profile_Field;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %transforms %defaults $cache_field );
$debug = 0;
$table = 'company_profile_fields';
$serial = 'company_profile_fields_id_seq';
%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
	'required'	=>	'required',
	'description'	=>	'description',
	'type'			=>	'type',	
	'sort'			=>	'sort',
	'values'		=>	'values',
	'deleted'		=>	'deleted',
	'searchable'	=>	'searchable',
	'search_default'	=>	'search_default',
	'match'			=>	'match',
	'on_registration'	=>	'on_registration',
	'viewable'			=>	'viewable',
	'defaults'		=>	'defaults',
);
%transforms = (
	'sort'	=> [ 's/\D//g' ],
);
%defaults = (
	'required'	=>	0,
	'searchable'	=>	0,
	'sort'		=>	'undef',
	'deleted'	=>	0,
	'on_registration'	=>	0,
	'viewable'	=>	1,
);
$cache_field = 'name';
sub cache_field {
	return $cache_field;
}

sub destroy {
	my $error;
	my $ac = sql::start_transaction( $openprint::dbh );
	foreach ( openprint::Company_Profile_Entry( 'field_id'=>$_[0]{'id'} ) ) {
		$error .= $_->destroy();
		if ( $error ) {
			$openprint::dbh->rollback();
			return $error;
		} # end if
	} # end foreach
	$error .= $_[0]->SUPER::destroy();
	sql::end_transaction( $openprint::dbh, $ac );
	return $error;
} # end sub destroy

sub html {
	my $html;
	
	my $Field = $_[0];

	$html .= '<li class="'.$Field->type(). ( $Field->required() ? ' required' : '' ) . '">
    <label>'.$Field->description().'</label>
    <div id="field-'.$Field->id().'_container">';
	my $value = $_[1] ? $_[1] : ( $_[0]->defaults() ? join(',',@{$_[0]->defaults()}) : '' );

	if ( $Field->type() eq 'checkbox' ) {
		foreach my $v ( ref $Field->values() eq 'ARRAY' ? @{$Field->values()} : () ) {
			$html .= sprintf( q`<input type="checkbox" name="field-%1$d" id="field-%1$d%2$s" value="%2$s" %3$s />
				<label class="radio" for="field-%1$d%2$s">%2$s</label>
				`, $Field->id(), $v, ssi::checked( sets::isin( $v, [ split(',', $value ) ] ) )
				);
		} # end foreach value
	} elsif ( $Field->type() eq 'date' ) {
		my ( $start, $end ) = @{$Field->values()} if $Field->values();
#$openprint::log->debug("Adding date start $start end $end value $value ");
		$html .= ssi::date_select( 'field-'.$Field->id(), $value, { start=>$start, end=>$end } );
#$openprint::log->debug("Done");
	} elsif ( $Field->type() eq 'country' ) {
		my $StateField = openprint::Company_Profile_Field->find_one(type=>'state');
		if ( $StateField ) {

			$html .= sprintf( q`<select id="field-%1$d" name="field-%1$d" onchange="Location_onchange( this, this.form.elements['field-%3$d'], 'state' );$('field-%1$d_name').value='';"><option value=""> </option>%2$s</select>
			 or other <input type="text" name="field-%1$d_name" id="field-%1$d_name" onkeyup="if(this.value){ddm_select_by_text_case_insensitive( $('field-%1$d'), this.value, 0 );}"/>`, $Field->id(),
			ssi::make_drop_down( openprint::Location->dropdown('order'=>'lower(name)','type'=>'country'), $value ),
			$StateField->id(),
			);
		} else {
			$html .= sprintf( q`<select id="field-%1$d" name="field-%1$d"><option value=""> </option>%2$s</select>
			 or other <input type="text" name="field-%1$d_name" id="field-%1$d_name" />`, $Field->id(),
			ssi::make_drop_down( openprint::Location->dropdown('order'=>'lower(name)','type'=>'country'), $value ),
			);
		} # end if
	} elsif ( $Field->type() eq 'state' ) {
		my $CityField = openprint::Company_Profile_Field->find_one(type=>'city');
		if ( $CityField ) {
			$html .= sprintf( q`<select id="field-%1$d" name="field-%1$d" onchange="Location_onchange( this, this.form.elements['field-%3$d'], 'city' );$('field-%1$d_name').value='';"><option value=""> </option>%2$s</select>
					or other <input type="text" name="field-%1$d_name" id="field-%1$d_name" onkeyup="if(this.value){ddm_select_by_text_case_insensitive( $('field-%1$d'), this.value, 0 );}" />
					`, $Field->id(),
					ssi::make_drop_down( openprint::Location->dropdown('order'=>'lower(name)','type'=>['state','province']), $value ),
					$CityField->id(),
					);
		} else {
			$html .= sprintf( q`<select id="field-%1$d" name="field-%1$d"><option value=""> </option>%2$s</select>
					or other <input type="text" name="field-%1$d_name" id="field-%1$d_name" />
					`, $Field->id(),
					ssi::make_drop_down( openprint::Location->dropdown('order'=>'lower(name)','type'=>['state','province']), $value ),
					);
		} # end if
	} elsif ( $Field->type() eq 'city' ) {
		$html .= sprintf( q`<select id="field-%1$d" name="field-%1$d" onchange="$('field-%1$d_name').value='';"><option value=""> </option>%2$s</select>
				or other <input type="text" name="field-%1$d_name" id="field-%1$d_name" onkeyup="if(this.value){ddm_select_by_text_case_insensitive( $('field-%1$d'), this.value, 0 );}" />
				`, $Field->id(),
				ssi::make_drop_down( openprint::Location->dropdown( order=>'lower(name)', type=>'city'), $value ),
				);
	} elsif ( $Field->type() eq 'place' ) {

		$openprint::log->debug("Value for place: $value");
if ( 1 ) {
		$html .= sprintf(q`<input type="text" id="field-%1$d" name="field-%1$d" value="%2$s"/>
				<div id="field-%1$d_autocomplete" class="autocomplete" style="display:none;">
				<script>
new Ajax.Autocompleter('field-%1$d','field-%1$d_autocomplete', '_locations.html?type=place', { minChars: 2,afterUpdateElement : getSelectionId } );
</script>
`, $Field->id(), new openprint::Location($value)->name() );
} else {

		$html .= sprintf( q`<select id="field-%1$d" name="field-%1$d" onchange="$('field-%1$d_name').value='';"><option value=""> </option>%2$s</select>
				or other <input type="text" name="field-%1$d_name" id="field-%1$d_name" onkeyup="ddm_select_by_text_case_insensitive( $('field-%1$d'), this.value, 0 );" />
				`, $Field->id(),
				ssi::make_drop_down( openprint::Location->dropdown('order'=>'lower(name)','type'=>'place'), $value ),
				);
}

	} elsif ( $Field->type() eq 'select-one' ) {
		my @values;
		if ( $value and ! sets::isin( $value, $Field->values() ) ) {
			@values = ($value, @{$Field->values()});
$openprint::log->debug("value not in values: $value NOT IN (@values)");
		} else {
			@values = @{$Field->values()};
$openprint::log->debug("value in values: $value IN (@values)");
			#*values = $Field->values();
		}

		$html .= ssi::select( [ map { $_, $_ } @values ], $value, { name=>'field-'.$$Field{id}, id=>'field-'.$$Field{id}, prepend=>['',' '] } );

	} elsif ( $Field->type() eq 'text' ) {
		$html .= sprintf( q`<input type="text" name="field-%1$d" id="field-%1$d" value="%2$s" />`, $Field->id(), $value );
	} elsif ( $Field->type() eq 'tel' ) {
		$html .= sprintf( q`<input type="tel" name="field-%1$d" id="field-%1$d" value="%2$s" />`, $Field->id(), $value );
	} elsif ( $Field->type() eq 'email' ) {
		$html .= sprintf( q`<input type="email" name="field-%1$d" id="field-%1$d" value="%2$s" />`, $Field->id(), $value );
	} elsif ( $Field->type() eq 'number' ) {
		$html .= sprintf( q`<input type="number" name="field-%1$d" id="field-%1$d" value="%2$s" />`, $Field->id(), $value );
	} elsif ( $Field->type() eq 'radio' ) {
		$html .= ssi::radio( 'field-'.$Field->id(), $Field->values(), $value );
	} # end if
	$html .= "</div></li>\n";
	return $html;
} # end sub html
1;
__END__
