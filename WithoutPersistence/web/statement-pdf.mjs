// Offline raster PDF: browser-rendered glyphs preserve all supported languages without remote fonts.
// This module receives only locally rendered JPEG bytes; it never fetches or uploads report data.
export function statementPDF(pages) {
  if (!Array.isArray(pages) || !pages.length) throw Error('PDF requires at least one page');
  const encode = text => new TextEncoder().encode(text);
  const chunks = [], offsets = [0]; let length = 0;
  const append = bytes => { chunks.push(bytes); length += bytes.length; };
  const text = value => append(encode(value));
  const object = (id, body) => { offsets[id] = length; text(`${id} 0 obj\n${body}\nendobj\n`); };
  const stream = (id, dictionary, bytes) => {
    offsets[id] = length; text(`${id} 0 obj\n<< ${dictionary} /Length ${bytes.length} >>\nstream\n`);
    append(bytes); text('\nendstream\nendobj\n');
  };
  text('%PDF-1.4\n');
  object(1, '<< /Type /Catalog /Pages 2 0 R >>');
  object(2, `<< /Type /Pages /Count ${pages.length} /Kids [${pages.map((_,i)=>`${3+i*3} 0 R`).join(' ')}] >>`);
  pages.forEach((page,index) => {
    const {bytes,width,height,pixelWidth,pixelHeight} = page;
    if (!(bytes instanceof Uint8Array) || bytes.length<4 || bytes[0]!==255 || bytes[1]!==216 ||
        ![width,height,pixelWidth,pixelHeight].every(v=>Number.isFinite(v)&&v>0) ||
        !Number.isInteger(pixelWidth) || !Number.isInteger(pixelHeight)) throw Error('Invalid PDF page');
    const id=3+index*3;
    object(id, `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${width} ${height}] /Resources << /XObject << /Im0 ${id+1} 0 R >> >> /Contents ${id+2} 0 R >>`);
    stream(id+1, `/Type /XObject /Subtype /Image /Width ${pixelWidth} /Height ${pixelHeight} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode`, bytes);
    stream(id+2, '', encode(`q\n${width} 0 0 ${height} 0 0 cm\n/Im0 Do\nQ`));
  });
  const xref=length, count=3+pages.length*3;
  text(`xref\n0 ${count}\n0000000000 65535 f \n`);
  for(let id=1;id<count;id++)text(`${String(offsets[id]).padStart(10,'0')} 00000 n \n`);
  text(`trailer\n<< /Size ${count} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
  const result = new Uint8Array(length);let offset=0;
  for(const chunk of chunks){result.set(chunk,offset);offset+=chunk.length;}
  return result;
}
