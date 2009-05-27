package ## Hide from PAUSE
 MooseX::Dependent::Meta::TypeCoercion::Dependent;

use Moose;
extends 'Moose::Meta::TypeCoercion';

=head1 NAME

MooseX::Meta::TypeCoercion::Dependent - Coerce Dependent type constraints.

=head1 DESCRIPTION

This class is not intended for public consumption.  Please don't subclass it
or rely on it.  Chances are high stuff here is going to change a lot.

=head1 METHODS

This class defines the following methods.

=head add_type_coercions

method modification to throw exception should we try to add a coercion on a
dependent type that is already defined by a constraining value.  We do this
since defined dependent type constraints inherit their coercion from the parent
constraint.  It makes no sense to even be using dependent types if you know the
constraining value beforehand!

=cut

around 'add_type_coercions' => sub {
    my ($add_type_coercions, $self, @args) = @_;
    if($self->type_constraint->has_constraining_value) {
        Moose->throw_error("Cannot add type coercions to a dependent type constraint that's been defined.");
    } else {
        return $self->$add_type_coercions(@args);
    }
};


## These two are here until I can merge change upstream to Moose.  These are two
## very minor changes we can probably just put into Moose without breaking stuff
sub coerce {
    my $self = shift @_;
    my $coderef = $self->_compiled_type_coercion;
    return $coderef->(@_);
}

sub compile_type_coercion {
    my $self = shift;
    my @coercion_map = @{$self->type_coercion_map};
    my @coercions;
    while (@coercion_map) {
        my ($constraint_name, $action) = splice(@coercion_map, 0, 2);
        my $type_constraint = ref $constraint_name ? $constraint_name : Moose::Util::TypeConstraints::find_or_parse_type_constraint($constraint_name);

        unless ( defined $type_constraint ) {
            require Moose;
            Moose->throw_error("Could not find the type constraint ($constraint_name) to coerce from");
        }

        push @coercions => [
            $type_constraint->_compiled_type_constraint,
            $action
        ];
    }
    $self->_compiled_type_coercion(sub {
        my $thing = shift;
        foreach my $coercion (@coercions) {
            my ($constraint, $converter) = @$coercion;
            if ($constraint->($thing)) {
                local $_ = $thing;
                return $converter->($thing, @_);
            }
        }
        return $thing;
    });
}

=head1 SEE ALSO

The following modules or resources may be of interest.

L<Moose>, L<Moose::Meta::TypeCoercion>

=head1 AUTHOR

John Napiorkowski, C<< <jjnapiork@cpan.org> >>

=head1 COPYRIGHT & LICENSE

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;