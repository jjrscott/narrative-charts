#!/usr/bin/perl

use strict;

use Data::Dumper;
use FileHandle;
use Getopt::Long;


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
	elsif ($line =~ m!([^\ =\n(]+(?:\(([^\)]+)\))?)\s*=\s*([^\n]+)!)
	{
		$entries{$current_entry_name}{$1} = $3;
		
		if (defined $2)
		{
			my @refs = split ',', $2;
			foreach my $ref (@refs)
			{
				$entries{$current_entry_name}{';refs'}{$ref}++;
				$entries{$ref}{';refs'}{$current_entry_name}++;
			}
		}
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

my %current_maxXs_for_ys;
foreach my $entry_name (sort {$entries{$a}{';min-x'} <=> $entries{$b}{';min-x'}} keys %entries)
{
	if (length $entry_name && !exists $entries{$entry_name}{'_date'})
	{
		while (my ($y, $maxX) = each %current_maxXs_for_ys)
		{
			if (($maxX + 60*60*24*31*12*100) < $entries{$entry_name}{';min-x'})
			{
				delete $current_maxXs_for_ys{$y};
			}
		}
	
	
		# Add actor to a slot

		my $i = 1;
		my $y = 0;
		while (1)
		{
			$y = $i-1;#int($i/2)*(-1)**$i;
			if (!exists $current_maxXs_for_ys{$y})
			{
				last;
			}
			$i++;
		}		
	
		$current_maxXs_for_ys{$y} = $entries{$entry_name}{';max-x'};
		$entries{$entry_name}{';y'} = $y;
		$entries{''}{';min-y'} = min($entries{''}{';min-y'}, $entries{$entry_name}{';y'});
		$entries{''}{';max-y'} = max($entries{''}{';max-y'}, $entries{$entry_name}{';y'});
		foreach my $ref (keys %{$entries{$entry_name}{';refs'}})
		{
			$entries{$ref}{';min-y'} = min($entries{$ref}{';min-y'}, $entries{$entry_name}{';y'});
			$entries{$ref}{';max-y'} = max($entries{$ref}{';max-y'}, $entries{$entry_name}{';y'});
		}
	}
}

$entries{''}{';min-x'} += -60*60*24*356.2425*50;
$entries{''}{';max-x'} += 60*60*24*356.2425*150;
$entries{''}{';min-y'} += -10;
$entries{''}{';max-y'} += 10;

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
		if ($key =~ m!^;!)
		{
# 			next;
		}
		if ('HASH' eq ref $entries{$entry_name}{$key})
		{
			printf $timeline_handle qq(%s = %s\n), $key, join ',', sort {$a cmp $b} keys %{$entries{$entry_name}{$key}};
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

my $svg_handle = FileHandle->new(">".$entries{''}{'output-path'});

print $svg_handle qq(<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n);
printf $svg_handle qq(<?xml-stylesheet href="%s" type="text/css"?>\n), $entries{''}{'xml-stylesheet'};

printf $svg_handle qq(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="%s" height="%s">\n), xT($entries{''}{';max-x'})-xT($entries{''}{';min-x'}), yT($entries{''}{';max-y'})-yT($entries{''}{';min-y'});

print $svg_handle qq(<title>OpenTimeLine</title>);

#-----------------------------------------------------------------------------------------

print $svg_handle qq(  <!-- All the events -->\n);

my $event_top = 0.5;
my $event_bottom = 0;

my $event_padding_top = 0;
my $event_padding_left = 0.5;
my $event_padding_bottom = 0.5;
my $event_padding_right = 0.5;

my @paintables;

my @sort_indexes =
(
	[qr/^$/]
);


foreach my $entry_name (keys %entries)
{
	foreach my $key (keys %{$entries{$entry_name}})
	{
		for (my $sort_index = 0;$sort_index<=@sort_indexes;$sort_index++)
		{
			if ($sort_index<@sort_indexes)
			{
				my ($entry_name_regex, $key_regex, $value_regex) = @{$sort_indexes[$sort_index]};
				$entry_name_regex ||= qr/.*/;
				$key_regex ||= qr/.*/;
				$value_regex ||= qr/.*/;
				if (($entry_name =~ $entry_name_regex && $key =~ $key_regex && $entries{$entry_name}{$key} =~ $value_regex))
				{
					push @paintables, [$entry_name, $key, $sort_index];
					last;
				}
			}
			else
			{
				push @paintables, [$entry_name, $key, $sort_index];
			}
		}
	}
}

foreach my $paintable (sort {$a->[2] cmp $b->[2] || $a->[1] cmp $b->[1] || $entries{$a->[0]}{$a->[1]} cmp $entries{$b->[0]}{$b->[1]}} @paintables)
{
	my ($entry_name, $key) = @{$paintable};
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
			printf $svg_handle qq(  <circle cx="%s" cy="%s" r="3" %s="%s" _type="event"><title>%s</title></circle>\n), xT($entries{$entry_name}{';x'}), yT($entries{$ref}{';y'}), $class, $entries{$entry_name}{$key}, escape($entries{$entry_name}{$key});
		}
		elsif ($key eq 'title')
		{
			my $minY = $entries{$entry_name}{';min-y'};
			$minY -= $event_top;
			printf $svg_handle qq(  <text x="%s" y="%s" _type="event">%s</text>\n),  xT($entries{$entry_name}{';x'})+2, yT($minY)-2, $entries{$entry_name}{$key};
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
				printf $svg_handle qq(  <polyline points="%s,%s %s,%s" _date="%s" _type="event"><title>%s</title></polyline>\n), xT($entries{$entry_name}{';x'}), yT($minY), xT($entries{$entry_name}{';x'}), yT($entries{$entry_name}{';max-y'}+$event_bottom), $entries{$entry_name}{'_date'}, $entries{$entry_name}{'_date'};
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
			
			my $start_x;
			my $end_x;
			my $left_margin;
			my $right_margin;
			
			if (length $start_ref)
			{
				$start_x = $entries{$start_ref}{';x'};
				$left_margin = 7;
			}
			else
			{
				$start_x = $entries{''}{';min-x'};
				$left_margin = 0;
			}
			
			if (length $end_ref)
			{
				$end_x = $entries{$end_ref}{';x'};
				$right_margin = 7;
			}
			else
			{
				$end_x = $entries{''}{';max-x'};
				$right_margin = 0;
			}
			

			if ($class eq 'name' && length $value)
			{
					printf $svg_handle qq(  <text _type="actor" x="%s" y="%s">%s</text>\n),  xT($start_x)+3, yT($entries{$entry_name}{';y'})-3, escape($entries{$entry_name}{$key});
			}
			elsif ($class eq 'website' && length $value)
			{
				printf $svg_handle qq(  <a xlink:href="%s"><polyline points="%s,%s %s,%s" _type="actor" %s="%s"/></a>\n), $value, xT($start_x)+$left_margin, yT($entries{$entry_name}{';y'}), xT($end_x)-$right_margin, yT($entries{$entry_name}{';y'}), $class, $value;
			}
			else
			{
				printf $svg_handle qq(  <polyline points="%s,%s %s,%s" _type="actor" %s="%s"/>\n), xT($start_x), yT($entries{$entry_name}{';y'}), xT($end_x), yT($entries{$entry_name}{';y'}), $class, $value;
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
	return int((($y - $entries{''}{';min-y'})) * 30);
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
	my ($a, $b) = @_;
	if (!defined $a)
	{
		return $b;
	}
	elsif (!defined $b)
	{
		return $a;
	}
	elsif ($a > $b)
	{
		return $a;
	}
	else
	{
		return $b;
	}
}

sub min
{
	my ($a, $b) = @_;
	if (!defined $a)
	{
		return $b;
	}
	elsif (!defined $b)
	{
		return $a;
	}
	elsif ($a < $b)
	{
		return $a;
	}
	else
	{
		return $b;
	}
}

sub escape
{
	my ($value) = @_;
	$value =~ s/&/&amp;/g;
	return $value;
}