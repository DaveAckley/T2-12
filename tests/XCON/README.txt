tests/XCON:

  This directory is for tests designed to run when a T2 tile is fully
  cross-connected to itself with ribbon cables, so the following
  intertile connections are made:

    ET <-> WT      NE <-> SW        NW <-> SE

  within each of those connections, the following pin connections are
  made:

      IGRLK <-> OGRLK        TXRDY <-> RXRDY
      IRQLK <-> ORQLK        TXDAT <-> RXDAT
  
 Note those two lines specify a total of sixteen connections, since
 each ITC has all eight of those pins.
