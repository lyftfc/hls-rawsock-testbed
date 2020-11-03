#!/usr/bin/python3
import xml.etree.ElementTree as ET
import zipfile
from shutil import copy2
import os
import sys

def parseIpXml(xmlPath):
    XNS = '{http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009}'
    SIMFS = 'xilinx_verilogbehavioralsimulation_view_fileset'
    ipComp = ET.parse(xmlPath).getroot()
    ipSpec = {}
    ipSpec['Name'] = ipComp.find(XNS + 'name').text
    ipPorts = {}
    for port in ipComp.find(XNS + 'model').find(XNS + 'ports'):
        pName = port.find(XNS + 'name').text
        pw = port.find(XNS + 'wire')
        pDir = pw.find(XNS + 'direction').text
        pVec = pw.find(XNS + 'vector')
        if pVec is not None:
            pVecL = int(pVec.find(XNS + 'left').text)
            pVecR = int(pVec.find(XNS + 'right').text)
            ipPorts[pName] = (pDir, pVecL, pVecR)
        else:
            ipPorts[pName] = (pDir)
    ipSpec['Ports'] = ipPorts
    ipVlogSrc = []
    ipMemInit = []
    for fset in ipComp.find(XNS + 'fileSets'):
        if fset.find(XNS + 'name').text == SIMFS: 
            ipfs = fset; break
    for f in ipfs.findall(XNS + 'file'):
        ftype = f.find(XNS + 'fileType')
        if ftype is None:
            if f.find(XNS + 'userFileType').text == 'mif':
                ipMemInit.append(f.find(XNS + 'name').text)
        elif ftype.text == 'verilogSource':
            ipVlogSrc.append(f.find(XNS + 'name').text)            
    ipSpec['VlogSrc'] = ipVlogSrc
    ipSpec['MemInit'] = ipMemInit
    return ipSpec

def inferAxis(portDict):
    # Expects input format: dict{signal_name: ('in'|'out'[, MSB_ID, LSB_ID]), ...}
    # Output format: dict{axis_stream_name: ('in'|'out', num_data_bits), ...}
    axiStreams = {}
    for k in portDict:
        if k.endswith('_V_TDATA'):
            sName = k[:-8]
            if len(portDict[k]) == 3:
                dWidth = portDict[k][1] - portDict[k][2] + 1
            else: dWidth = 0
            axiStreams[sName] = (portDict[k][0], dWidth)
    for k in axiStreams:
        if not (k + '_V_TVALID' in portDict and k + '_V_TREADY' in portDict):
            # Note that this does not check signal width and direction
            print("W: Discarded incomplete AXI Stream " + k + ".")
            axiStreams.pop(k)
    return axiStreams

def inferPuPorts(axiStreams):
    # Expects input format: dict{axis_stream_name: ('in'|'out', num_data_bits), ...}
    # Output format: (puIn{port_name: num_bytes, ...}, puOut{...})
    puIn = {}
    puOut = {}
    for s in axiStreams:
        if s.endswith('_V_data'):
            puName = s[:-7]
            if axiStreams[s][1] % 8 != 0:
                print("W: Discarded PU " + puName + " due to fractional bytes data width.")
                continue
            puBytes = int(axiStreams[s][1] / 8)
            if axiStreams[s][0] == 'in':
                puIn[puName] = puBytes
            else:
                puOut[puName] = puBytes
    for p in puIn:
        if not (p + '_V_flags' in axiStreams and p + '_V_eop' in axiStreams):
            # Again, this does not check signal width and direction
            print("W: Discarded incomplete PU port " + p + ".")
            puIn.pop(p)
    for p in puOut:
        if not (p + '_V_flags' in axiStreams and p + '_V_eop' in axiStreams):
            # Again, this does not check signal width and direction
            print("W: Discarded incomplete PU port " + p + ".")
            puOut.pop(p)
    return (puIn, puOut)

def writeSimTop(svPath, dutName, puDef, intfName = "s1-eth#"):
    # Input format of puDef: (puIn[], puOut[], puWidth)
    # Read template
    with open("../testbed/sim_top.sv.template", "r") as tmplt:
        sv = tmplt.readlines()
    # Construct port number and names
    nPorts = max(len(puDef[0]), len(puDef[1]))
    pNames = '"'
    for i in range(nPorts):
        pNames += intfName.replace('#', str(i + 1)) + ' '
    pNames = pNames[:-1] + '"'
    # Constuct DUT connection list
    dutConn = ""
    for i in range(len(puDef[0])):  # puIn
        port = puDef[0][i]
        for attr in ['data', 'flags', 'eop']:
            for suf in [('TDATA','d'), ('TVALID','v'), ('TREADY','r')]:
                dutConn += '    .' + port + '_V_' + attr + '_V_' + suf[0]
                dutConn += '(pu_dutin_' + attr + '_' + suf[1] + '[' + str(i) + ']),\n'
    for i in range(len(puDef[1])):  # puOut
        port = puDef[1][i]
        for attr in ['data', 'flags', 'eop']:
            for suf in [('TDATA','d'), ('TVALID','v'), ('TREADY','r')]:
                dutConn += '    .' + port + '_V_' + attr + '_V_' + suf[0]
                dutConn += '(pu_dutout_' + attr + '_' + suf[1] + '[' + str(i) + ']),\n'
    dutConn = dutConn[:-2]
    # Replace and write to file
    for i in range(len(sv)):
        sv[i] = sv[i].replace("$(TB_NUM_PORT)", str(nPorts))
        sv[i] = sv[i].replace("$(TB_PU_WIDTH)", str(puDef[2]))
        sv[i] = sv[i].replace("$(TB_PORT_LIST)", pNames)
        sv[i] = sv[i].replace("$(TB_DUT_NAME)", dutName)
        sv[i] = sv[i].replace("$(TB_DUT_PORT_CONN)", dutConn)
    with open(svPath, "w") as svFile:
        svFile.writelines(sv)

if __name__ == "__main__":

    # Prepare build directory and IP archive
    if not os.path.isdir('build'): os.mkdir('build')
    if not os.path.isdir('build/ip'): os.mkdir('build/ip')
    if not os.path.exists('build/ip/component.xml'):
        if len(sys.argv) < 2:
            print("E: Require path to IP archive as first argument.")
            exit(-1)
        with zipfile.ZipFile(sys.argv[1], "r") as ipzip:
            ipzip.extractall("build/ip")
    
    # Enter working directory
    os.chdir('build')

    # Parse IP
    ips = parseIpXml('ip/component.xml')

    # Write XVlog Parser Project
    with open("xvlog-parse-ip.prj", "w") as parsePrj:
        for f in ips['VlogSrc']:
            parsePrj.write("sv xil_defaultlib ip/" + f + "\n")
    
    # Copy any memory init files to build root
    for f in ips['MemInit']:
        copy2("ip/" + f, ".")
    
    # Extract Packet Unit ports and check their width
    puPorts = inferPuPorts(inferAxis(ips['Ports']))
    puIn = list(puPorts[0].keys())
    puOut = list(puPorts[1].keys())
    puWidthList = list({**puPorts[0], **puPorts[1]}.values())
    puWidth = puWidthList[0]
    for w in puWidthList:
        if w != puWidth: 
            print("E: The testbed requires all PU ports of the same width.")
            exit(-1)

    # Prepare simulation top module
    if not os.path.exists("../sim_top.sv"):
        writeSimTop("../sim_top.sv", ips['Name'], (puIn, puOut, puWidth))