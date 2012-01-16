#!/usr/bin/ruby
require 'RMagick'

infile=""
ARGV.each { |a|
    infile=a
}

fheader=File.basename(infile, File.extname(infile))

margin=1.0/8
separators = 5	    # for 6 images
#fheader="out"

instrip = Magick::Image.read(infile).first
instrip.rotate!(-90, '<')
ds=instrip.rows/400.0
filmstrip=instrip.resize(1/ds)

rows=filmstrip.rows
cols =filmstrip.columns

acc = Array.new(cols)
maxp = 0
minp = 1000000

cols.times {|x|
    pixels = filmstrip.get_pixels(x,(rows*margin),1,(rows-rows*margin))
    i=0.0
    pixels.each { |p|
	val=p.intensity()
	if i < val
	    i=val
	end
    }

    acc[x] = i*1.0
    if acc[x] > maxp
	maxp = acc[x]
    end
    if acc[x] < minp
	minp = acc[x]
    end
}

acc.map! {|v| ((v)/(maxp))}
pstep = cols/(separators+1)
diffstep = pstep/10

mins=Array.new(separators+2)
mins[0]=0
mins[separators+1]=cols*ds-1

separators.times {|sep|
    pc = (sep+1)*pstep
    min=100000
    finp=-1
    ((pc-diffstep)..(pc+diffstep)).each {|p|
	if acc[p]<min
	    min=acc[p]
	    finp=p
	end }
#	print finp, " "
    mins[sep+1] = finp*ds
    
}

(0..(separators)).each {|i|
#    print i, " ", mins[i],"-", mins[i+1], "\n"
    outimg=instrip.crop(mins[i],0,mins[i+1]-mins[i],instrip.rows,true)
    fname=format("%s.%03d.tif", fheader, i)
    outimg.write(fname)
    print "size: ", mins[i+1]-mins[i],"\n"}



	
pix=Array.new(1)
pix[0]=Magick::Pixel.from_color('yellow')
cols.times {|x|
    v=acc[x]*rows*0.9
    filmstrip.store_pixels(x,(rows-v),1,1,pix)}

pix[0]=Magick::Pixel.from_color('cyan')
mins.each {|p|
    filmstrip.store_pixels(p/ds,rows-1,1,1,pix)}

#filmstrip.view(0,0,cols,rows) do |view|
#    acc.each_with_index {|v,i| view[v][i]='yellow'}
#end

filmstrip.write("testout.tif")
#cols.times {|x|
#    acc

#printf("Max: %f	\t min: %f\n", maxp, minp)



