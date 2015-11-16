use v6;

=begin pod

=head1 NAME

URI::Template - implementation of RFC 6570

=head1 SYNOPSIS

=begin code

use URI::Template;

my $template = URI::Template.new(template => 'http://foo.com{/foo,bar}');

say $template.process(foo => 'baz', bar => 'quux'); # http://foo.com/baz/quux

=end code

=head1 DESCRIPTION

This provides an implementation of
L<RFC6570|https://tools.ietf.org/html/rfc6570> which allows for the
definition of a URI through variable expansion.

=head1 METHODS

=head2 method new

=head2 method process

=end pod

class URI::Template:ver<v0.0.1>:auth<github:jonathanstowe> {

    use URI::Encode;

    has Str $.template is rw;

    # this holds the parsed parts
    has @.parts;


    #| Simply a marker to indicate whether encoding need happen
    role PreEncoded {

    }

    class Variable {
        has Str $.name;
        has Int $.max-length;
        has Bool $.explode;

        method get-value(Str $operator, %vars) returns Str {
            my Str $value;

            if %vars{$!name}:exists {
                $value = self.expand-value($operator, %vars{$!name});

            }

            $value;
        }

        multi method expand-value(Str $operator, $value) {
            my Str $exp-value;


            if $!max-length {
                $exp-value = $value.substr(0, $!max-length);
            }
            else {
                $exp-value = $value;
            }
            $exp-value;
        }

        multi method expand-value(Str $operator, @value) {

            my $joiner = self.get-joiner($operator);
            my Str $exp-value = @value.map(&uri_encode_component).join($joiner);

            $exp-value does PreEncoded;

            return $exp-value;
        }

        multi method expand-value(Str $operator, %value) {
            say "hash";

        }

        method get-joiner(Str $operator) returns Str {
            my $joiner = self.explode ?? $operator // ',' !! ',';
            $joiner;
        }

        multi method process(Str:U $, %vars) {
            my Str $res;

            if self.get-value(Str, %vars) -> $val {
                $res = uri_encode_component($val);
            }
            $res;
        }

        multi method process('+', %vars) {
            my Str $res;

            if self.get-value('+', %vars) -> $val {
                $res = uri_encode($val);
            }
            $res;
        }

        multi method process('/', %vars) {
            my Str $res;

            if self.get-value('/',%vars) -> $val {
                $res = uri_encode($val);
            }
            $res;
        }

        multi method process('#', %vars) {
            my Str $res;

            if self.get-value('#', %vars) -> $val {
                $res = uri_encode($val);
            }
            $res;
        }

        multi method process('&', %vars ) {
            my Str $res = $!name ~ '=';

            if self.get-value('&', %vars) -> $val {
                $res ~= uri_encode_component($val);
            }
            $res;

        }

        multi method process(';', %vars ) {
            my Str $res = $!name;

            if self.get-value(';', %vars) -> $val {
                $res ~= '=' ~ uri_encode($val);
            }
            $res;
        }

        multi method process('?', %vars ) {
            my Str $res = $!name ~ '=';

            if self.get-value('?', %vars) -> $val {
                $res ~= uri_encode_component($val);
            }
            $res;
        }

        multi method process('.', %vars ) {
            my Str $res;

            if self.get-value('.', %vars) -> $val {
                $res = uri_encode($val);
            }
            $res;
        }

    }

    sub get-joiner(Str $operator) {
        my $joiner = do given $operator {
            when '/' {
                '/';
            }
            when '&' {
                '&';
            }
            when '?' {
                '&';
            }
            when '.' {
                '.';
            }
            when ';' {
                ';';
            }
            default {
                ',';
            }
        }

        $joiner;

    }

    class Expression {
        has $.operator;
        has Variable @.variables;

        method process(%vars) returns Str {
            my Str $str;

            my @processed-bits;

            for self.variables -> $variable {
               @processed-bits.push($variable.process($!operator, %vars));
            }

            my $joiner = get-joiner($!operator);
            $str = @processed-bits.join($joiner);

            if $!operator.defined && $!operator ne '+' {
                $str = $!operator ~ $str;
            }

            $str;
        }
    }

    has Grammar $.grammar = our grammar Grammar {
        rule TOP {
            <bits>* [ <expression>+ ]* %% <bits>+ 
        }

        token bits { <-[{]>+ }

        regex expression {
            '{' <operator>? <variable>+ % ',' '}'
        }

        regex operator {
            <reserved>          || 
            <fragment>          || 
            <label-dot>         || 
            <path-slash>        ||
            <path-semicolon>    ||
            <form-ampersand>    ||
            <form-continuation>


        }

        token reserved {
            '+'
        }
        token fragment {
            '#'
        }

        token label-dot {
            '.'
        }

        token path-slash {
            '/'
        }

        token path-semicolon {
            ';'
        }

        token form-ampersand {
            '?'
        }

        token form-continuation {
            '&'
        }

        regex variable {
            <variable-name><var-modifier>?
        }
        regex variable-name {
            <.ident>
        }

        rule var-modifier {
            <explode> || <prefix>
        }

        token explode {
            '*'
        }
        token prefix {
            ':' <max-length>
        }
        token max-length {
            \d+
        }
    }

    our class Actions {

        has @.PARTS = ();
        has Match $!last-bit;

        method TOP($/) {
            $/.make(@!PARTS);
        }

        method bits($/) {
            # This shouldn't be necessary but I can't work out why
            # the last bit is duplicated
            if !$!last-bit.defined || $/.from  != $!last-bit.from {
                @!PARTS.push($/.Str);
            }
            $!last-bit = $/;
        }

        method expression($/) {
            my $operator =  $/<operator>.defined ?? $/<operator>.Str !! Str;
            my @variables = $/<variable>.list.map({ $_.made }); 
            @!PARTS.push(Expression.new(:$operator, :@variables));
        }

        method variable($/) {

            my Str $name = $/<variable-name>.Str;
            my Int $max-length;
            my Bool $explode = False;

            my $vm = $/<var-modifier>;

            if $vm.defined {
                $max-length = $vm<prefix><max-length>.defined ?? $vm<prefix><max-length>.Int !! Int;
                $explode = $vm<explode>.defined;
            }
            $/.make(Variable.new(:$name, :$max-length, :$explode));
        }

    }

    class X::NoTemplate is Exception {
        has $.message = "Template is not defined";
    }

    class X::InvalidTemplate is Exception {
        has $.message = "Invalid or un-parseable template";
    }

    method parts() {
        if not @!parts.elems {

            if $!template.defined {

            
                my $actions = Actions.new;

                my $match = URI::Template::Grammar.parse($!template, :$actions);

                if $match {
                    @!parts = $match.made;
                }
                else {
                    X::InvalidTemplate.new.throw;
                }
            }
            else {
                X::NoTemplate.new.throw;
            }
        }
        @!parts;
    }

    method process(*%vars) returns Str {
        my Str $string;

        for self.parts -> $part {
            given $part {
                when Str {
                    $string ~= $part
                }
                when Expression {
                    $string ~= $part.process(%vars);
                }
                default {
                    die "Unexpected object of type { $part.WHAT.name } found in parsed template";

                }
            }
        }

        $string;
    }


}
# vim: expandtab shiftwidth=4 ft=perl6
