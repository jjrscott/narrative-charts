#!/usr/bin/perl

use strict;

use Data::Dumper;
use FileHandle;
use Getopt::Long;
use File::Slurp;


my %override_global_entry;

GetOptions
(
	'value=s' => \%override_global_entry,
) or die;

my ($timeline_path) = @ARGV;

my $timeline_handle = FileHandle->new($timeline_path) or die;

my %entries;
my $current_entry_name;

my %event_entries;

while (my $line = $timeline_handle->getline())
{
	$line =~ s!\n!!;
	$line =~ s!;.*!!;
	if ($line =~ m!\[([^\]]+)\]!)
	{
		$current_entry_name = $1;
	}
	elsif ($line =~ m!([^\ =\n(]+(?:\(([^\)]+)\))?)\s*=\s*([^\n]*)!)
	{
		$entries{$current_entry_name}{$1} = $3;
		
		if (defined $2)
		{
			my @refs = split ',', $2;
			foreach my $ref (@refs)
			{
				$entries{$current_entry_name}{';refs'}{$ref} = undef;
				$entries{$ref}{';refs'}{$current_entry_name} = undef;
			}
		}
# 		die Dumper([$current_entry_name, $1, $2, $3]);
	}
	elsif ($line =~ m!^\s*$!)
	{
	}
	else
	{
		die $line;
	}
}

foreach my $entry_name (keys %entries)
{
	if (length $entry_name && exists $entries{$entry_name}{'_date'})
	{
		$entries{$entry_name}{';x'} = parse_datetime($entries{$entry_name}{'_date'});
		$entries{''}{';min-x'} = min($entries{''}{';min-x'}, $entries{$entry_name}{';x'});
		$entries{''}{';max-x'} = max($entries{''}{';max-x'}, $entries{$entry_name}{';x'});
		
		foreach my $ref (keys %{$entries{$entry_name}{';refs'}})
		{
			$entries{$ref}{';min-x'} = min($entries{$ref}{';min-x'}, $entries{$entry_name}{';x'});
			$entries{$ref}{';max-x'} = max($entries{$ref}{';max-x'}, $entries{$entry_name}{';x'});
		}
	}
}

my %visible_entry_names;
foreach my $entry_name (sort {$entries{$a}{';x'} <=> $entries{$b}{';x'}} keys %entries)
{
	if (length $entry_name && exists $entries{$entry_name}{'_date'})
	{		
		foreach my $visible_entry_name (keys %visible_entry_names)
		{
			if (($entries{$visible_entry_name}{';max-x'} + 60*60*24*31*12*100) < $entries{$entry_name}{';x'})
			{
				delete $visible_entry_names{$visible_entry_name};
			}
			
# 			my $y = 0;
# 			foreach my $visible_entry_name (sort {$visible_entry_names{$a} <=> $visible_entry_names{$b}} keys %visible_entry_names)
# 			{
# 				$visible_entry_names{$visible_entry_name} = $y++;
# 				$entries{$visible_entry_name}{';points'}{$entries{$entry_name}{';x'}} = $visible_entry_names{$visible_entry_name};
# 			}
		}
		
		foreach my $ref (keys %{$entries{$entry_name}{';refs'}})
		{
			$entries{$ref}{';min-x'} = min($entries{$ref}{';min-x'}, $entries{$entry_name}{';x'});
			$entries{$ref}{';max-x'} = max($entries{$ref}{';max-x'}, $entries{$entry_name}{';x'});
			
			my $i = 1;
			my $y = 0;
			
			if (exists $visible_entry_names{$ref})
			{
				$y = $visible_entry_names{$ref};
			}
			else
			{
				my %used_ys = reverse %visible_entry_names;
				for(;;$y++)
				{
					if (!exists $used_ys{$y})
					{
						last;
					}
				}
				$visible_entry_names{$ref} = $y;
			}	

			$visible_entry_names{$ref} = $y;
			$entries{$ref}{';points'}{$entries{$entry_name}{';x'}} = $y;
			$entries{''}{';min-y'} = min($entries{''}{';min-y'}, $y);
			$entries{''}{';max-y'} = max($entries{''}{';max-y'}, $y);
			$entries{$entry_name}{';min-y'} = min($entries{$entry_name}{';min-y'}, $y);
			$entries{$entry_name}{';max-y'} = max($entries{$entry_name}{';max-y'}, $y);
		}
	}
}

#die Dumper(\%visible_entry_names);

$entries{''}{';min-x'} += parse_datetime(exists $entries{''}{'margin-left'} ? -$entries{''}{'margin-left'} : '-100');
$entries{''}{';max-x'} += parse_datetime(exists $entries{''}{'margin-right'} ? $entries{''}{'margin-right'} : '100');
$entries{''}{';min-y'} += exists $entries{''}{'margin-top'} ? -$entries{''}{'margin-top'} : -2;
$entries{''}{';max-y'} += exists $entries{''}{'margin-bottom'} ? $entries{''}{'margin-bottom'} : 2;

my $timeline_handle = FileHandle->new('>'.$timeline_path) or die;

my $first = 1;

foreach my $entry_name (sort {$a cmp $b} keys %entries)
{
	if (!$first)
	{
		print $timeline_handle qq(\n);
	}
	$first = 0;
	if (length $entry_name)
	{
		printf $timeline_handle qq([%s]\n), $entry_name;
	}
	foreach my $key (sort {$a cmp $b} keys %{$entries{$entry_name}})
	{
# 		if ($key eq 'type' || $key eq 'name')
# 		{
# 			my (@refs) = sort {$entries{$a}{';x'} <=> $entries{$b}{';x'}} keys %{$entries{$entry_name}{';refs'}};
# 			printf $timeline_handle qq(%s(%s,%s) = %s\n), $key, $refs[0], $refs[-1], $entries{$entry_name}{$key};
# 			next;
# 		}
	
		if ($key =~ m!^;!)
		{
			next;
		}
		if ('HASH' eq ref $entries{$entry_name}{$key})
		{
			printf $timeline_handle qq(%s = %s\n), $key, join ' ', map {$_.(defined $entries{$entry_name}{$key}{$_}? ','.$entries{$entry_name}{$key}{$_} : '')} sort {$a cmp $b} keys %{$entries{$entry_name}{$key}};
		}
		else
		{
			printf $timeline_handle qq(%s = %s\n), $key, $entries{$entry_name}{$key};
		}
	}
}

foreach my $key (keys %override_global_entry)
{
	$entries{''}{$key} = $override_global_entry{$key};
}

my $output_path = $entries{''}{'output-path'};
if (0 == length $output_path)
{
	$output_path = $timeline_path;
	$output_path =~ s!\.[^\.]*$!.svg!;
}

my $svg_handle = FileHandle->new(">".$output_path);

my $xml_stylesheet = $entries{''}{'xml-stylesheet'};
if (0 == length $xml_stylesheet)
{
	$xml_stylesheet = $timeline_path;
	$xml_stylesheet =~ s!\.[^\.]*$!.css!;
}


print $svg_handle qq(<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n);
# printf $svg_handle qq(<?xml-stylesheet href="%s" type="text/css"?>\n), $xml_stylesheet;

printf $svg_handle qq(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="%s" height="%s">\n), xT($entries{''}{';max-x'})-xT($entries{''}{';min-x'}), yT($entries{''}{';max-y'})-yT($entries{''}{';min-y'});

print $svg_handle qq(<title>OpenTimeLine</title>);

printf $svg_handle qq(<style type="text/css">\n<![CDATA[\n%s]]>\n</style>\n), scalar read_file($xml_stylesheet);

#-----------------------------------------------------------------------------------------

print $svg_handle qq(  <!-- All the events -->\n);

my $event_top = 0.3;
my $event_bottom = 0;

my $event_padding_top = 0;
my $event_padding_left = 0.5;
my $event_padding_bottom = 0.5;
my $event_padding_right = 0.5;

my @paintables;

my @sort_indexes =
(
	['', undef],
	['event','_date'],
	['event','type'],
	['actor','entity'],
	['actor','title'],	
	['event','participant', 'back'],
	['event','title', 'back'],
	['actor','name', 'back'],
	['event','title'],
	['actor','name'],
	['actor','website'],
# 	['event','participant'],
);


foreach my $entry_name (keys %entries)
{
	my $type = 'actor';
	if ('' eq $entry_name)
	{
		$type = '';
	}
	elsif (exists $entries{$entry_name}{'_date'})
	{
		$type = 'event';
	}
	foreach my $key (keys %{$entries{$entry_name}})
	{
		next if $key =~ m!^;!;
		my ($trimmed_key) = $key =~ m!^([^(]+)!;
		my $matched = 0;
		for (my $sort_index = 0;$sort_index<@sort_indexes;$sort_index++)
		{

			my ($type_match, $key_match, $level) = @{$sort_indexes[$sort_index]};
			if ((!defined $type_match || $type_match eq $type) && (!defined $key_match || $key_match eq $trimmed_key))
			{
				push @paintables, [$entry_name, $key, $sort_index, $level];
				$matched++;
			}
		}
		if ($matched == 0)
		{
			die sprintf qq(Failed to match %s / %s for entry %s\n), $type, $key, $entry_name;
		}
	}
}
my $id_count = 0;
foreach my $paintable (sort {$a->[2] <=> $b->[2] || $a->[1] cmp $b->[1] || $entries{$a->[0]}{$a->[1]} cmp $entries{$b->[0]}{$b->[1]}} @paintables)
{
	my ($entry_name, $key, undef, $order) = @{$paintable};

	if (0 == length $entry_name)
	{
		if ($key eq 'period-marker-width')
		{
			my $strip_width = parse_datetime($entries{''}{'period-marker-width'});

			my $period = 0;
			for (my $x=(int($entries{''}{';min-x'}/$strip_width)-1)*$strip_width;$x < $entries{''}{';max-x'}; $x+=$strip_width)
			{
				printf $svg_handle qq(  <rect x="%s" y="%s" width="%s" height="%s" _type="period"/>\n), xT($x), yT($entries{''}{';min-y'}), xT($strip_width+$x)-xT($x), yT($entries{''}{';max-y'})-yT($entries{''}{';min-y'}),;
			}
		}
	}
	elsif (exists $entries{$entry_name}{'_date'})
	{
		my ($class, $ref) = $key =~ m!([^ =\n(]+)\(([^\)]+)\)!;
		if (defined $class)
		{
			printf $svg_handle qq(  <circle cx="%s" cy="%s" r="5" %s="%s" _type="event" _order="%s"><title>%s: %s</title></circle> <!-- %s -->\n), xT($entries{$entry_name}{';x'}), yT($entries{$ref}{';points'}{$entries{$entry_name}{';x'}}), $class, $entries{$entry_name}{$key}, $order, escape($entries{$entry_name}{'_date'}), escape($entries{$entry_name}{$key}), $entry_name;
		}
		elsif ($key eq 'title')
		{
			my $minY = $entries{$entry_name}{';min-y'};
			$minY -= $event_top;
			printf $svg_handle qq(  <text x="%s" y="%s" _type="event" _order="%s">%s</text>\n),  xT($entries{$entry_name}{';x'})+2, yT($minY)-2, $order, $entries{$entry_name}{$key};
			
			
# 				printf $svg_handle qq(  <defs><path id="%s" d="M%s %s L%s %s" _date="%s" _type="event"><title>%s</title></path></defs>\n), $id_count, xT($entries{$entry_name}{';x'}), yT($minY), xT($entries{$entry_name}{';x'}), yT($entries{$entry_name}{';max-y'}+$event_bottom), $entries{$entry_name}{'_date'}, $entries{$entry_name}{'_date'};
# 			
# 				printf $svg_handle qq(  <text _type="actor" x="10"><textPath _order="back" xlink:href="#%s">%s</textPath></text>\n), $id_count, escape($entries{$entry_name}{$key});
# 
# 				printf $svg_handle qq(  <text _type="actor" x="10"><textPath _order="front" xlink:href="#%s">%s</textPath></text>\n), $id_count, escape($entries{$entry_name}{$key});
# 
# 				$id_count++;
		}
		elsif (length $entry_name && $key eq '_date')
		{
			my $minY = $entries{$entry_name}{';min-y'};
			if (length $entries{$entry_name}{'title'})
			{
				$minY -= $event_top;
			}
	
			if ($minY != $entries{$entry_name}{';max-y'})
			{
				printf $svg_handle qq(  <path d="M%s %s L%s %s" _date="%s" _type="event"><title>%s</title></path>\n), xT($entries{$entry_name}{';x'}), yT($minY), xT($entries{$entry_name}{';x'}), yT($entries{$entry_name}{';max-y'}+$event_bottom), $entries{$entry_name}{'_date'}, $entries{$entry_name}{'_date'};
			}
		}
	}
	else
	{
		my ($class, $start_ref, $end_ref) = $key =~ m!([^ =\n(]+)\(([^,]*),([^\)]*)\)!;

		if (defined $class)
		{
			my $value = $entries{$entry_name}{$key};

			$value =~ s/&/&amp;/g;
			
			my @xs = sort {$a <=> $b} keys %{$entries{$entry_name}{';points'}};
			
			if (0 == length $start_ref)
			{
				unshift @xs, $entries{''}{';min-x'};
			}
			
			if (0 == length $end_ref)
			{
				push @xs, $entries{''}{';max-x'};
			}
			
			my @points;
			for (my $xi=0;$xi<@xs;$xi++)
			{
				if (length $start_ref && $xs[$xi] < $entries{$start_ref}{';x'})
				{
					next;
				}
				if (length $end_ref && $xs[$xi] > $entries{$end_ref}{';x'})
				{
					next;
				}
				my $y;
				if (exists $entries{$entry_name}{';points'}{$xs[$xi]})
				{
					$y = $entries{$entry_name}{';points'}{$xs[$xi]};
				}
				elsif ($xi == 0)
				{
					$y = $entries{$entry_name}{';points'}{$xs[$xi+1]};
				}
				else
				{
					$y = $entries{$entry_name}{';points'}{$xs[$xi-1]};
				}
				push @points, xT($xs[$xi]).','.yT($y);
			}
			

			if ($class eq 'name' && length $value)
			{
				my ($x, $y) = split ',', $points[-1];
				push @points, ($x+1000).','.$y;
				
				printf $svg_handle qq(  <defs><path id="%s" d="M%s" _type="actor" %s="%s"/></defs>\n),$id_count, join(' L', @points), $class, $value, $entry_name;

			
				printf $svg_handle qq(  <text _type="actor" x="5"><textPath _order="%s" xlink:href="#%s">%s</textPath></text>\n), $order, $id_count, escape($entries{$entry_name}{$key});
				
				$id_count++;
			}
			elsif ($class eq 'website' && length $value)
			{
				printf $svg_handle qq(  <a xlink:href="%s"><path d="M%s" _type="actor" %s="%s"/></a>\n), $value, join(' L', @points), $class, $value;
			}
			else
			{
				printf $svg_handle qq(  <path d="M%s" _type="actor" %s="%s"/> <!-- %s -->\n), join(' L', @points), $class, $value, $entry_name;
			}
		}
	}
}

print $svg_handle qq(</svg>);

exit(0);

sub xT
{
	my ($x) = @_;
	my $xT = int(($x - $entries{''}{';min-x'}) * $entries{''}{'scale-x'});
	#printf "%20.5f %20d\n", $x,$xT;
	return $xT;
}

sub yT
{
	my ($y) = @_;
	return int((($y - $entries{''}{';min-y'})) * $entries{''}{'scale-y'});
}
sub parse_datetime
{
	my ($datetime) = @_;
	my ($year, $month, $day, $hour, $min, $sec) = split /[:\/ ]/, $datetime;
	  
	my $x = $year;
	$x *= 12;
	$x += ($month - 1);
	$x *= 31;
	$x += ($day - 1);
	$x *= 24;
	$x += $hour;
	$x *= 60;
	$x += $min;
	$x *= 60;
	$x += $sec;
	
	return $x;
}

sub max
{
	my $r = undef;
	foreach my $v (@_)
	{
		if (!defined $r || $v > $r)
		{
			$r = $v;
		}
	}
	return $r;
}

sub min
{
	my $r = undef;
	foreach my $v (@_)
	{
		if (!defined $r || $v < $r)
		{
			$r = $v;
		}
	}
	return $r;
}

sub escape
{
	my ($value) = @_;
	$value =~ s/&/&amp;/g;
	return $value;
}