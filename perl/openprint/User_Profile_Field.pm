use strict;
package openprint::User_Profile_Field;
our @ISA = qw( openprint::Object );

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;
$table = 'user_profile_fields';
$serial = 'user_profile_fields_id_seq';
%fields = (
	'id'	=>	'id',
	'name'	=>	'name',
	'required'	=>	'required',
	'description'	=>	'description',
	type			=>	'type',	
	'sort'			=>	'sort',
	'values'		=>	'values',
	'defaults'		=>	'defaults',
	'searchable'	=>	'searchable',
	'deleted'		=>	'deleted',
	'search_default'	=>	'search_default',
	'match'			=>	'match',
	'on_registration'	=>	'on_registration',
	'viewable'			=>	'viewable',
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

sub destroy {
	my $error;
	my $ac = sql::start_transaction( $openprint::dbh );
	foreach ( openprint::User_Profile_Entry( 'field_id'=>$_[0]{'id'} ) ) {
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

	$html .= '<li class="'.$Field->type().'"><label>'.$Field->description().'</label><span id="field-'.$Field->id().'_container">';
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
		$html .= '<span class="DateSelector">'.ssi::date_select( 'field-'.$Field->id(), $value, { 'start'=>$start, 'end'=>$end } ) . '</span>';
#$openprint::log->debug("Done");

	} elsif ( $Field->type() eq 'location' ) {
		$html .= '<ul class="location">';
		my $Location = new openprint::Location( $value );
		my $Country = $Location->ancestor(type=>'country');
		my $country_id = $Country->id() if $Country;
		$Country = new openprint::Location() if ! $country_id;
		my $State = $Location->ancestor(type=>'state');
		my $state_id = $State->id() if $State;
		my $City = $Location->ancestor(type=>'city');
		my $city_id = $City->id() if $City;

		my @Countries = openprint::Location->find(order=>'lower(name)',type=>'country');
		my @States = openprint::Location->find(order=>'lower(name)',type=>'state',
            ( sets::isin( $country_id, [ map { $_->id() } @Countries ] ) ? ( 'parent_id'=>$country_id ) : () ),
            );
		my @Cities = openprint::Location->find('order'=>'lower(name)','type'=>'city',
				( sets::isin( $state_id, [ map { $_->id() } @States ] ) ? ( 'parent_id'=>$state_id ) : () ),
				);

		my $prefix = 'field-'.$$Field{id}.'-';

		$html .= '<li class="country"><label>Country</label>';
		$html .= ssi::select( [ '', 'All', map { $_->id(), $_->name() } @Countries ], $country_id, { name=>$prefix.'country_id', id=>$prefix.'country_id', onchange=>qq`Location_onchange( this, 'country' );\$('${prefix}country').value='';` } );

		$html .= qq` or other <input type="text" name="${prefix}country" id="${prefix}country" onkeyup="if(this.value){ddm_select_by_text_case_insensitive( \$('${prefix}country_id'), this.value, 0 );}"/>`;
		$html .= '</li><li class="state"><label>';
		if ( $Country->name() eq 'Canada' ) {
			$html .= 'Province';
		} elsif ( $Country->name() eq 'United States' ) {
			$html .= 'State';
		} else {
			$html .= 'State/Province';
		} # end if
		$html .= '</label>';
		$html .= ssi::select( [ '', 'All', map { $_->id(), $_->name() } @States ], $state_id, { name=>$prefix.'state_id', id=>$prefix.'state_id', onchange=>qq`Location_onchange( this, 'state' );\$('${prefix}state').value='';` } );

		$html .= qq` or other <input type="text" name="${prefix}state" id="${prefix}state" onkeyup="if(this.value){ddm_select_by_text_case_insensitive( \$('${prefix}state_id'), this.value, 0 );}"/>`;
		$html .= '</li><li class="city"><label>City</label>';
		$html .= ssi::select( [ '', 'All', map { $_->id(), $_->name() } @Cities ], $city_id, { name=>$prefix.'city_id', id=>$prefix.'city_id', onchange=>qq`\$(${prefix}'city').value='';` } );
		$html .= q` or other <input type="text" name="${prefix}city" id="${prefix}city" onkeyup="if(this.value){ddm_select_by_text_case_insensitive( \$('${prefix}city_id'), this.value, 0 );}"/>`; 
		$html .= '</li>';
		#$html .= sprintf('<li><label>Address</label><input type="text" name="address" id="address" value="%s" /></li>', $Location->address() );
		$html .= sprintf('<li><label>Postal/Zip Code</label><input type="text" name="%1$spostalcode" id="%1$spostalcode" value="%2$s"/></li>', $prefix, $Location->postalcode() );
		$html .= '</ul>';
	} elsif ( $Field->type() eq 'country' ) {
		# Have to look up the child element so we can update it
		my $StateField = openprint::User_Profile_Field->find_one(type=>'state');
		my $CityField = openprint::User_Profile_Field->find_one(type=>'city');
		my $options = join(',',
				( $StateField ? "state_element: 'field-$$StateField{id}'" : '' ),
				( $CityField ? "city_element: 'field-$$CityField{id}'" : '' ),
			);
		$options = ', { ' . $options . '}' if $options;
		

			$html .= sprintf( q`<select id="field-%1$d" name="field-%1$d" onchange="Location_onchange( this, 'country'%3$s );$('field-%1$d_name').value='';"><option value=""> </option>%2$s</select>
					or other <input type="text" name="field-%1$d_name" id="field-%1$d_name" onkeyup="if(this.value){ddm_select_by_text_case_insensitive( $('field-%1$d'), this.value, 0 );}"/>`, $Field->id(),
					ssi::make_drop_down( openprint::Location->dropdown(order=>'lower(name)',type=>'country'), $value ),
					$options,
					);
	} elsif ( $Field->type() eq 'state' ) {
		my $CityField = openprint::User_Profile_Field->find_one(type=>'city');
		my $options = join(',',
				( $CityField ? "city_element: 'field-$$CityField{id}'" : '' ),
			);
		$options = ', { ' . $options . '}' if $options;
			$html .= sprintf( q`<select id="field-%1$d" name="field-%1$d" onchange="Location_onchange( this, 'state'%3$s );$('field-%1$d_name').value='';"><option value=""> </option>%2$s</select>
					or other <input type="text" name="field-%1$d_name" id="field-%1$d_name" onkeyup="if(this.value){ddm_select_by_text_case_insensitive( $('field-%1$d'), this.value, 0 );}" />
					`, $Field->id(),
					ssi::make_drop_down( openprint::Location->dropdown(order=>'lower(name)',type=>['state','province']), $value ),
					$options,
					);
	} elsif ( $Field->type() eq 'city' ) {
		$html .= sprintf( q`<select id="field-%1$d" name="field-%1$d" onchange="$('field-%1$d_name').value='';"><option value=""> </option>%2$s</select>
				or other <input type="text" name="field-%1$d_name" id="field-%1$d_name" onkeyup="if(this.value){ddm_select_by_text_case_insensitive( $('field-%1$d'), this.value, 0 );}" />
				`, $Field->id(),
				ssi::make_drop_down( openprint::Location->dropdown(order=>'lower(name)',type=>'city'), $value ),
				);
	} elsif ( $Field->type() eq 'place' ) {

		$openprint::log->debug("Value for place: $value");
if ( 1 ) {
		$html .= sprintf(q`<input type="text" id="field-%1$d" name="field-%1$d" value="%2$s"/>
				<div id="field-%1$d_autocomplete" class="autocomplete" style="display:none;">
				<script type="text/javascript">
new Ajax.Autocompleter('field-%1$d','field-%1$d_autocomplete', '_locations.html?type=place', { minChars: 2,afterUpdateElement : getSelectionId } );
</script>
`, $Field->id(), new openprint::Location($value)->name() );
} else {

		$html .= sprintf( q`<select id="field-%1$d" name="field-%1$d" onchange="$('field-%1$d_name').value='';"><option value=""> </option>%2$s</select>
				or other <input type="text" name="field-%1$d_name" id="field-%1$d_name" onkeyup="ddm_select_by_text_case_insensitive( $('field-%1$d'), this.value, 0 );" />
				`, $Field->id(),
				ssi::make_drop_down( openprint::Location->dropdown(order=>'lower(name)',type=>'place'), $value ),
				);
}

	} elsif ( $Field->type() eq 'select-one' ) {
		$html .= sprintf( q`<select name="field-%1$d" id="field-%1$d"><option value=""> </option>`, $Field->id() );
		$html .= ssi::make_drop_down( [ map { $_, $_ } @{$Field->values()} ], $value );
		$html .= '</select>';
	} elsif ( $Field->type() eq 'text' ) {
		$html .= sprintf( q`<input type="text" name="field-%1$d" id="field-%1$d" value="%2$s" />`, $Field->id(), $value );
	} elsif ( $Field->type() eq 'email' ) {
		$html .= sprintf( q`<input type="email" name="field-%1$d" id="field-%1$d" value="%2$s" />`, $Field->id(), $value );
	} elsif ( $Field->type() eq 'number' ) {
		$html .= sprintf( q`<input type="number" name="field-%1$d" id="field-%1$d" value="%2$s" />`, $Field->id(), $value );
	} elsif ( $Field->type() eq 'radio' ) {
		$html .= ssi::radio( 'field-'.$Field->id(), $Field->values(), $value );
	} # end if
	$html .= "</span></li>\n";
	return $html;
} # end sub html
1;
__END__
