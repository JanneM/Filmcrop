#!/usr/bin/ruby
#
# Filmcrop - crop scanned film strips into individual frames
#
# Copyright (C) 2012  Jan Morén
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

# v. 0.1 Initial public version

require 'RMagick'
require 'optparse'

$diff_fac=0.25	# fraction frame width to search for an edge
$margin=1./8.0	# ignored top and bottom area
$ds=nil		# scale factor for the small images we work with

fheader="crop"
images=6

dofit=true
fitsize=0
doaverage=true

# create the intensity array corresponding to a given strip

def make_intense(fstrip)

    rows=fstrip.rows
    cols =fstrip.columns

    acc = Array.new(cols)
    maxp = 0
    cols.times {|col|
	pixels = fstrip.get_pixels(col,(rows*$margin),1,(rows-2*rows*$margin))
	#mp = pixels.max_by{|p| p.intensity()}.intensity()*1.0
	mpix = pixels.max_by{|p| [p.red(),p.green(),p.blue()].max}
	mp = [mpix.red(),mpix.green(),mpix.blue()].max*1.0

	maxp = mp if mp > maxp
	acc[col] = mp
    }
    acc.map! {|v| ((v)/(maxp))}
end

# Find the minima in the neighbourhood around each possible separation point

def find_minima(arr, frames)
    pstep = arr.length/frames
    diffstep = Integer(pstep*$diff_fac)

    mins=Array.new(frames+1)
    mins[0]=0
    mins[frames]=arr.length-1

    (1..frames-1).each {|f|
	pc_min=f*pstep-diffstep
	pc_max=f*pstep+diffstep
	(min, minp) = arr[pc_min..pc_max].each_with_index.min
	mins[f] = minp+pc_min
    }
    mins
end

# find least square minima of pairs of points
def find_sqr_minima(strip, frames, framesize)
    arr = strip.intensity
    pstep = arr.length/(frames)
    diffstep = Integer(pstep*$diff_fac)

    mins=Array.new(frames)

    (1..frames-2).each {|f|

	ps = Integer(f*pstep)
	pe = Integer(ps+framesize)

	arr_start=arr.slice(ps-diffstep..ps+diffstep)
	arr_end=arr.slice(pe-diffstep..pe+diffstep)
	ms=arr_start.min
	me=arr_end.min
	arr_start.map! {|x| x-ms}
	arr_end.map! {|x| x-me}

	minp=arr_start.zip(arr_end).each_with_index.min_by {|ap,i|
	    ap[0]**2+ap[1]**2}[1]-diffstep

	mins[f]=[(ps+minp)*$ds, (pe+minp)*$ds]
    }
    mins[0]=[(mins[1][0]-framesize*$ds), (mins[1][0])]
    mins[frames-1]=[mins[frames-2][1], mins[frames-2][1]+framesize*$ds]
    mins
end

optparse = OptionParser.new { |opts|

    opts.banner="Usage: filmcrop [options] file1 file2 .."
    opts.on( '-i', '--images N', Integer, 'Number of images on a strip (default 6)' ) do |f|
	images=f
	if images<2
	    puts "Need at least two images per strip\n\n", opts
	    exit
	end
    end
    opts.on( '-f', "--[no-]fit=[SIZE]", Integer, "Fit the average frame size or given frame [SIZE] to every image (default)") do |f|
	if f==nil
	    dofit = true    # default
	    doaverage=true
	elsif f==false
	    dofit = false
	else
	    dofit = true
	    doaverage=false
	    fitsize=f
	end

    end
    opts.on( '-o', '--output FILE', 'Set output file name prefix (default "crop")' ) do |f|
	fheader=f
    end

    opts.on_tail( '-h', '--help', 'Print this help text' ) do
	puts opts
	exit
    end
}
begin optparse.parse!
rescue OptionParser::ParseError => e
    puts e, "\n", optparse
    exit 1
end

files = ARGV
if files.length < 1
    print "Need at least one input file.\n"
    puts optparse
    exit(0)
end

Img = Struct.new(:fname,	# Full size file name
		 :intensity,	# average value array
		 :cuts,		# found cut positions
		 :fcut,		# final frame cuts
		 :row, :col)	# size of the scaled-down image 

strips=Array.new()

files.each {|infile|

    print "Processing file: ", infile, "\n"
    begin instrip = Magick::Image.read(infile).first
    rescue Magick::ImageMagickError => e
	puts e, "\n", optparse
	exit 1
    end

    instrip.rotate!(-90, '<')
    $ds=$ds||instrip.rows/200.0
    strip=instrip.resize(1/$ds)
    instrip.destroy!

    arr=make_intense(strip)
    cuts=find_minima(arr, images)
    
    if false
    pix=Array.new(1)
    pix[0]=Magick::Pixel.from_color('yellow')
    strip.columns.times {|x|
        v=arr[x]*strip.rows*0.9
        strip.store_pixels(x,(strip.rows-v-1),1,1,pix)}

#    pix[0]=Magick::Pixel.from_color('cyan')
#    cuts.each {|p|
#        strip.store_pixels(p/ds,rows-1,1,1,pix)}
    strip.write("testout.tif")

    exit()
    end
    a=Array.new()
    strips.push(Img.new(infile, arr, cuts,a, strip.rows, strip.columns))
    strip.destroy!
}

# fit to an average or given frame width 
if dofit
    print "fitting... "
    avg=0
    if doaverage		    # find average frame size
	total=0
	nr=0
	strips.each {|s|
	    (1..(images-2)).each {|i|	    # note '1'
		total+=(s.cuts[i+1]-s.cuts[i])
		nr+=1
	    }
	}
	if nr>0
	   avg = Integer(total/nr)
	else
	    print "This is going to end badly...\n"
	end
	print "Estimated size: ", Integer(avg*$ds), " pixels\n"
    else			    # use user-supplied size
	avg=fitsize/$ds
	print "\n"
    end
    strips.each {|s|
	s.fcut=find_sqr_minima(s, images, avg)
    }
# No fixed frame, so just set the cuts at each local minimum
else			
    strips.each {|s|
	(0..(images-1)).each {|i|
	    f=[s.cuts[i]*$ds, s.cuts[i+1]*$ds]
	    s.fcut.push(f)
	}
    }
end

filenr=1
strips.each {|s|
    print "crop file: ", s.fname, "\n"
    begin instrip = Magick::Image.read(s.fname).first
    rescue Magick::ImageMagickError => e
	print s.fname, " has magically disappeared!\n"
	exit 1
    end
    instrip.rotate!(-90, '<')
    (0..(images-1)).each {|i|
	cuts=s.fcut[i]

	outimg=instrip.crop(cuts[0],0,(cuts[1]-cuts[0]),instrip.rows,true)
	fname=format("%s.%03d.tif", fheader, filenr)
	filenr+=1
	outimg.write(fname)
	print "\t f# ", i, "\n"
	outimg.destroy!
    }
    instrip.destroy!
}

