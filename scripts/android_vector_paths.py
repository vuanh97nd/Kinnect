"""Convert compact SVG arc flags to Android-compatible path arguments."""
import math
import re
COUNTS = {'M':2, 'L':2, 'H':1, 'V':1, 'C':6, 'S':4, 'Q':4, 'T':2, 'A':7, 'Z':0}
NUMBER = re.compile(r'[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?')
COMMAND = re.compile(r'[MmLlHhVvCcSsQqTtAaZz]')

def normalize_svg_path(source):
    at, output = 0, []
    while at < len(source):
        while at < len(source) and source[at] in ' \t\r\n,': at += 1
        if at == len(source): break
        command = source[at]
        if command.upper() not in COUNTS: raise ValueError('Expected SVG command at '+str(at))
        if not output and command.upper() != 'M': raise ValueError('Path must start with M/m')
        at += 1
        output.append(command)
        count = COUNTS[command.upper()]
        if not count: continue
        values = []
        while True:
            while at < len(source) and source[at] in ' \t\r\n,': at += 1
            if at == len(source) or COMMAND.match(source, at): break
            if command.upper() == 'A' and len(values) % 7 in (3, 4):
                if source[at] not in '01': raise ValueError('Arc flag must be 0 or 1')
                values.append(source[at]); at += 1
            else:
                match = NUMBER.match(source, at)
                if not match: raise ValueError('Expected SVG number at '+str(at))
                value = match.group()
                if not math.isfinite(float(value)): raise ValueError('Non-finite path number')
                values.append(value); at = match.end()
        if not values or len(values) % count: raise ValueError('Incomplete '+command+' argument group')
        output.extend(values)
    normalized = ' '.join(output)
    validate_android_path(normalized)
    return normalized

def validate_android_path(source):
    matches = list(COMMAND.finditer(source))
    if not matches or source[:matches[0].start()].strip() or matches[0].group().upper() != 'M':
        raise ValueError('Native path must start with M/m')
    for index, match in enumerate(matches):
        command = match.group().upper()
        end = matches[index+1].start() if index+1 < len(matches) else len(source)
        arguments = source[match.end():end]
        values = NUMBER.findall(arguments)
        if NUMBER.sub('', arguments).strip(' \t\r\n,'): raise ValueError('Invalid native number')
        count = COUNTS[command]
        if (count == 0 and values) or (count and (not values or len(values) % count)):
            raise ValueError(command+' requires complete groups of '+str(count)+' floats, got '+str(len(values)))
        if any(not math.isfinite(float(value)) for value in values): raise ValueError('Non-finite native number')
        if command == 'A':
            for start in range(0, len(values), 7):
                if any(float(values[start+flag]) not in (0,1) for flag in (3,4)):
                    raise ValueError('Native arc flags must be separated 0/1 values')
    return True
